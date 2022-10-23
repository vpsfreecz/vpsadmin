require 'fileutils'
require 'tempfile'

module NodeCtld
  class Commands::Vps::VzToOs < Commands::Base
    handle 2024
    needs :system, :osctl, :vps

    include OsCtl::Lib::Utils::File

    def exec
      # Ensure the container is mounted
      osctl(%i(ct mount), @vps_id)

      # Call distribution-dependent conversion code
      m_convert = :"convert_#{@distribution}"

      if respond_to?(m_convert, true)
        m_args = []

        # Configurable context, if any. The context method can be used to pass
        # data to the forked-and-chrooted convert method.
        m_ctx = :"context_#{@distribution}"
        m_args << send(m_ctx) if respond_to?(m_ctx, true)

        begin
          fork_chroot_wait do
            @rootfs = '/'
            send(m_convert, *m_args)
          end
        ensure
          # Cleanup context, if any
          m_cleanup = :"cleanup_#{@distribution}"
          send(m_cleanup, *m_args) if respond_to?(m_cleanup, true)
        end
      end

      m = :"runscript_#{@distribution}"
      if respond_to?(m, true)
        tmp = Tempfile.create(['nodectld', '.sh'])
        tmp.puts('#!/bin/sh')
        tmp.puts(send(m))
        tmp.close

        begin
          osctl(
            %i(ct runscript),
            [@vps_id, tmp.path],
            {run_container: true, network: true}
          )
        ensure
          begin
            File.unlink(tmp.path)
          rescue SystemCallError
            # pass
          end
        end
      end

      ok
    end

    def rollback
      ok
    end

    protected
    def context_alpine
      {
        'cgroups-mount.initscript' => File.open(File.join(
          NodeCtld.root, 'templates/vz_to_os', 'alpine_cgroups-mount.initscript'
        )),
      }
    end

    def cleanup_alpine(ctx)
      ctx['cgroups-mount.initscript'].close
    end

    def convert_alpine(ctx)
      regenerate_file(File.join(@rootfs, 'etc/inittab'), 0644) do |new, old|
        if old.nil?
          new.puts('# vpsAdmin console')
          new.puts('::respawn:/sbin/getty 38400 console')
        else
          old.each_line do |line|
            if line =~ /^#{Regexp.escape('::respawn:/sbin/getty 38400 tty0')}/
              new.puts('::respawn:/sbin/getty 38400 console')
            else
              new.write(line)
            end
          end
        end
      end

      File.open(File.join(@rootfs, 'etc/init.d/cgroups-mount'), 'w') do |f|
        IO.copy_stream(ctx['cgroups-mount.initscript'], f)
      end

      add_export_mounts_to_fstab
    end

    def runscript_alpine
      if @mounts_to_exports.any?
        <<END
type mount.nfs || apk add nfs-utils
rc-update add nfsmount
END
      else
        "exit 0\n"
      end
    end

    def convert_arch
      remove_systemd_overrides
      disable_systemd_udev_trigger
      ensure_journal_log
      add_export_mounts_to_fstab
    end

    def convert_centos
      convert_redhat

      fstab = File.join(@rootfs, 'etc/fstab')

      if File.exist?(fstab)
        regenerate_file(fstab, 0644) do |new, old|
          old.each_line do |line|
            if line.start_with?('#')
              new.write(line)
              next
            end

            fs, mountpoint = line.split

            next if fs == 'none' && %w(/dev/pts /dev/shm).include?(mountpoint)
            new.write(line)
          end
        end
      end

      # Create an upstart service on centos < 7 to handle graceful shutdown
      init = File.join(@rootfs, 'etc/init')
      shutdown = File.join(init, 'shutdown.conf')

      if Dir.exist?(init) && !File.exist?(shutdown)
        File.open(shutdown, 'w') do |f|
          f.puts(<<END
description "Trigger an immediate shutdown on SIGPWR"
start on power-status-changed

task
exec shutdown -h now "SIGPWR received"
END
          )
        end
      end

      # Patch/create tty services for centos < 7
      if Dir.exist?(init)
        regenerate_file(File.join(init, 'console.conf'), 0644) do |new, old|
          if old
            old.each_line do |line|
              if /^#{Regexp.escape('exec /sbin/mingetty')}/ =~ line
                new.puts('exec /sbin/agetty 38400 console')
              else
                new.write(line)
              end
            end

          else
            new.puts(<<END
start on stopped rc RUNLEVEL=[2345]
stop on runlevel [!2345]
respawn
exec /sbin/agetty 38400 console
END
            )
          end
        end

        tty2 = File.join(init, 'tty2.conf')
        File.unlink(tty2) if File.exist?(tty2)
      end

      # Disable /sbin/start_udev in /etc/rc.d/rc.sysinit on centos < 7
      rc_sysinit = File.join(@rootfs, 'etc/rc.d/rc.sysinit')

      if File.exist?(rc_sysinit)
        regenerate_file(rc_sysinit, 0755) do |new, old|
          next if old.nil?

          old.each_line do |line|
            if line.strip == '/sbin/start_udev'
              new.puts('# Disabled by migration to vpsAdminOS')
              new.puts('# /sbin/start_udev')
            else
              new.write(line)
            end
          end
        end
      end
    end

    def convert_debian
      major_version = get_debian_major_version

      convert_debian_systemd(major_version)
      convert_debian_inittab(major_version)

      add_export_mounts_to_fstab
      add_mount_all_to_debian_rc_local if major_version <= 8
    end

    def convert_debian_systemd(major_version)
      return unless Dir.exist?(File.join(@rootfs, 'etc/systemd'))

      if major_version == 8
        dir = File.join(@rootfs, 'etc/systemd/system/dbus.service.d')
        file = File.join(dir, 'override.conf')
        FileUtils.mkpath(dir)
        File.open(file, 'w') do |f|
          f.write(<<END
[Service]
OOMScoreAdjust=0
END
          )
        end
      end

      disable_systemd_udev_trigger
      ensure_journal_log
    end

    def convert_debian_inittab(major_version)
      inittab = File.join(@rootfs, 'etc/inittab')
      return unless File.exist?(inittab)

      have_power = false
      have_getty = false

      regenerate_file(inittab, 0644) do |new, old|
        old.each_line do |line|
          if line.lstrip.start_with?('#')
            new.write(line)

          elsif line =~ /^#{Regexp.escape('pf::powerwait:/etc/init.d/powerfail start')}/
            new.puts('pf::powerwait:/sbin/halt')
            have_power = true

          elsif line.include?('pf::powerwait:/sbin/halt')
            new.write(line)
            have_power = true

          elsif line.include?('getty') && line.include?('tty0')
            new.write("# Disabled by migration to vpsAdminOS")
            new.write("# #{line}")

          elsif line.include?('getty') && line.include?('console')
            new.write(line)
            have_getty = true

          else
            new.write(line)
          end
        end

        unless have_power
          new.puts('pf::powerwait:/sbin/halt')
        end

        getty_line =
          if File.exist?(File.join(@rootfs, 'sbin/agetty'))
            "c0:2345:respawn:/sbin/agetty --noreset 38400 console"
          elsif File.exist?(File.join(@rootfs, 'sbin/getty'))
            "c0:2345:respawn:/sbin/getty 38400 console"
          end

        if !have_getty && getty_line
          new.puts
          new.puts('# Start getty on /dev/console')
          new.puts(getty_line)
        end
      end
    end

    def runscript_debian
      <<END
installpkg() {
  local pkg=$1

  apt-get install -y $pkg && return 0
  apt-get update
  apt-get install -y $pkg
}

type ip || installpkg iproute
type ifup || installpkg ifupdown
#{@mounts_to_exports.any? ? 'type mount.nfs || installpkg nfs-common' : ''}
END
    end

    def context_devuan
      {
        'cgroups-mount.initscript' => File.open(File.join(
          NodeCtld.root, 'templates/vz_to_os', 'devuan_cgroups-mount.initscript'
        )),
      }
    end

    def cleanup_devuan(ctx)
      ctx['cgroups-mount.initscript'].close
    end


    def convert_devuan(ctx)
      inittab = File.join(@rootfs, 'etc/inittab')

      if File.exist?(inittab)
        regenerate_file(inittab, 0644) do |new, old|
          old.each_line do |line|
            if line =~ /^#{Regexp.escape('pf::powerwait:/etc/init.d/powerfail start')}/
              new.puts('pf::powerwait:/sbin/halt')
            else
              new.write(line)
            end
          end

          new.puts
          new.puts('# Start getty on /dev/console')
          new.puts('c0:2345:respawn:/sbin/agetty --noreset 38400 console')
        end
      end

      File.open(File.join(@rootfs, 'etc/init.d/cgroups-mount'), 'w') do |f|
        IO.copy_stream(ctx['cgroups-mount.initscript'], f)
      end

      add_export_mounts_to_fstab
    end

    alias_method :runscript_devuan, :runscript_debian

    def convert_gentoo
      inittab = File.join(@rootfs, 'etc/inittab')

      if File.exist?(inittab)
        regenerate_file(inittab, 0644) do |new, old|
          old.each_line do |line|
            if line =~ /^#{Regexp.escape('c0:2345:respawn:/sbin/agetty --noreset 38400 tty0')}/
              next
            else
              new.write(line)
            end
          end

          new.puts
          new.puts('# Start getty on /dev/console')
          new.puts('c0:2345:respawn:/sbin/agetty --noreset 38400 console')
          new.puts
          new.puts('# Clean container shutdown on SIGPWR')
          new.puts('pf:12345:powerwait:/sbin/halt')
        end
      end

      regenerate_file(File.join(@rootfs, 'etc/rc.conf'), 0644) do |new, old|
        if old.nil?
          new.puts('rc_sys="lxc"')
        else
          old.each_line do |line|
            if line =~ /^rc_sys=/
              new.puts('rc_sys="lxc"')
            else
              new.write(line)
            end
          end
        end
      end

      add_export_mounts_to_fstab
    end

    def convert_nixos
      sbin = File.join(@rootfs, 'sbin')
      sbin_init = File.join(sbin, 'init')
      bin_init = File.join(@rootfs, 'bin', 'init')

      if link_exist?(bin_init) && !link_exist?(sbin_init)
        Dir.mkdir(sbin) unless Dir.exist?(sbin)
        File.symlink('/bin/init', sbin_init)
      end
    end

    def convert_opensuse
      add_export_mounts_to_fstab
    end

    def runscript_opensuse
      if @mounts_to_exports.any?
        "type mount.nfs || zypper install -y nfs-utils"
      else
        "exit 0\n"
      end
    end

    def convert_ubuntu
      fstab = File.join(@rootfs, 'lib/init/fstab')

      if File.exist?(fstab)
        to_disable = [
          %w(none /proc/sys/fs/binfmt_misc binfmt_misc),
          %w(none /sys/kernel/debug debugfs),
        ]

        regenerate_file(fstab, 0644) do |new, old|
          old.each_line do |line|
            if line.lstrip.start_with?('#')
              new.write(line)
              next
            end

            cols = line.split

            if to_disable.include?(cols[0..2])
              new.puts(
                "# The following entry was commented by vpsAdmin when migrating\n"+
                "# to vpsAdminOS. Do not uncomment while running on vpsAdminOS."
              )
              new.write("# #{line}")
            else
              new.write(line)
            end
          end
        end
      end

      disable_systemd_udev_trigger
      ensure_journal_log
      add_export_mounts_to_fstab
      add_mount_all_to_debian_rc_local if @version.to_i <= 14
    end

    alias_method :runscript_ubuntu, :runscript_debian

    def convert_redhat
      remove_systemd_overrides

      # Remove obsolete ifcfg configs
      Dir.glob(File.join(
        @rootfs, 'etc', 'sysconfig', 'network-scripts', 'ifcfg-venet0:*'
      )).each do |file|
        File.unlink(file)
      end

      disable_systemd_udev_trigger
      ensure_journal_log
      add_export_mounts_to_fstab
    end

    def runscript_redhat
      if @mounts_to_exports.any?
        "type mount.nfs || yum install -y nfs-utils"
      else
        "exit 0\n"
      end
    end

    alias_method :convert_fedora, :convert_redhat
    alias_method :runscript_fedora, :runscript_redhat
    alias_method :runscript_centos, :runscript_redhat

    def convert_void
      begin
        File.unlink(File.join(@rootfs, 'etc/runit/core-services/90-venet.sh'))
      rescue Errno::ENOENT
      end

      add_export_mounts_to_fstab
    end

    def remove_systemd_overrides
      %w(systemd-journald systemd-logind).each do |sv|
        dir = File.join(@rootfs, 'etc/systemd/system', "#{sv}.service.d")
        next unless Dir.exist?(dir)

        file = File.join(dir, 'override.conf')
        next unless File.exist?(file)

        custom = false

        regenerate_file(file, 0644) do |new, old|
          old.each_line do |line|
            if line =~ /^SystemCallFilter=$/ || line =~ /^MemoryDenyWriteExecute=no/
              next
            elsif line =~ /^\[Service\]/
              new.write(line)
            else
              custom = true
              new.write(line)
            end
          end
        end

        File.unlink(file) unless custom

        begin
          Dir.rmdir(dir)
        rescue SystemCallError
          # pass
        end
      end
    end

    def disable_systemd_udev_trigger
      return unless Dir.exist?(File.join(@rootfs, 'etc/systemd/system'))

      f = File.join(@rootfs, 'etc/systemd/system/systemd-udev-trigger.service')
      File.lstat(f)
    rescue Errno::ENOENT
      File.symlink('/dev/null', f)
    end

    def ensure_journal_log
      return unless Dir.exist?(File.join(@rootfs, 'etc/systemd'))

      FileUtils.mkdir_p(File.join(@rootfs, 'var/log/journal'))
    end

    def add_export_mounts_to_fstab
      return if @mounts_to_exports.empty?

      File.open(File.join(@rootfs, 'etc/fstab'), 'a') do |f|
        f.puts

        @mounts_to_exports.each do |m|
          prefix = m['enabled'] ? '' : '# '

          opts = %w(vers=3)
          opts << 'nofail' if m['nofail']
          opts << 'ro' if m['mode'] == 'ro'

          f.puts("# Mount of dataset #{m['dataset_name']} (id=#{m['dataset_id']}) to #{m['mountpoint']}")
          f.puts("#{prefix}#{m['server_address']}:#{m['server_path']} #{m['mountpoint']} nfs #{opts.join(',')} 0 0")
          f.puts
        end
      end
    end

    def add_mount_all_to_debian_rc_local
      return if @mounts_to_exports.empty?

      regenerate_file(File.join(@rootfs, 'etc/rc.local'), 0755) do |new, old|
        if old.nil?
          old.puts('#!/bin/sh -e')
          old.puts('mount -a')
          old.puts('exit 0')
          next
        end

        added = false

        old.each_line do |line|
          if line.start_with?('exit ')
            new.puts('# Added by migration to vpsAdminOS to ensure NFS mounts')
            new.puts('mount -a')
            new.puts
            added = true
          end

          new.write(line)
        end

        unless added
          new.puts('# Added by migration to vpsAdminOS to ensure NFS mounts')
          new.puts('mount -a')
          new.puts
        end
      end
    end

    # @return [Integer, nil]
    def get_debian_major_version
      s = File.read(File.join(@rootfs, 'etc/debian_version')).strip

      if /^(\d+)\.(\d+)/ =~ s
        return $1.to_i
      elsif s.start_with?('jessie')
        return 8
      elsif s.start_with?('wheezy')
        return 7
      elsif s.start_with?('squeeze')
        return 6
      elsif s.start_with?('lenny')
        return 5
      end

      11
    end

    def link_exist?(path)
      File.lstat(path)
      true

    rescue Errno::ENOENT
      false
    end
  end
end
