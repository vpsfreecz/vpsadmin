require 'tempfile'

module NodeCtld
  class Commands::Vps::VzToOs < Commands::Base
    handle 2024
    needs :system, :osctl

    include OsCtl::Lib::Utils::File

    def exec
      # Ensure the container is mounted
      osctl(%i(ct mount), @vps_id)

      # Get path to its rootfs
      @rootfs = osctl_parse(%i(ct show), @vps_id)[:rootfs]

      # Call distribution-dependent conversion code
      m = :"convert_#{@distribution}"
      send(m) if respond_to?(m, true)

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
    def convert_alpine
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
    end

    def convert_arch
      remove_systemd_overrides
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
            File.open(console, 'w') do |f|
              f.puts(<<END
start on stopped rc RUNLEVEL=[2345]
stop on runlevel [!2345]
respawn
exec /sbin/agetty 38400 console
END
              )
            end
          end
        end

        tty2 = File.join(init, 'tty2.conf')
        File.unlink(tty2) if File.exist?(tty2)
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
END
    end

    def convert_devuan
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
      raise NotImplementedError
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
    end

    alias_method :convert_fedora, :convert_redhat

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

    def link_exist?(path)
      File.lstat(path)
      true

    rescue Errno::ENOENT
      false
    end
  end
end
