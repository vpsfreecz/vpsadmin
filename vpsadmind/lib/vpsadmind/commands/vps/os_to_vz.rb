require 'tempfile'

module VpsAdmind
  class Commands::Vps::OsToVz < Commands::Base
    handle 2025
    needs :system, :vz, :vps, :file

    def exec
      # Call distribution-dependent conversion code
      m = :"convert_#{@distribution}"
      if respond_to?(m, true)
        fork_chroot_wait do
          @rootfs = '/'
          send(m)
        end
      end

      m = :"runscript_#{@distribution}"
      if respond_to?(m, true)
        runscript(m, "#!/bin/sh\n#{send(m)}")
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
          new.puts('::respawn:/sbin/getty 38400 tty0')
        else
          old.each_line do |line|
            if line =~ /^#{Regexp.escape('::respawn:/sbin/getty 38400 console')}/
              new.puts('::respawn:/sbin/getty 38400 tty0')
            else
              new.write(line)
            end
          end
        end
      end
    end

    def convert_arch
      add_systemd_overrides
    end

    def convert_centos
      convert_redhat

      fstab = File.join(@rootfs, 'etc/fstab')

      if File.exist?(fstab) && @version.start_with?('6')
        has_pts = false
        has_shm = false

        regenerate_file(fstab, 0644) do |new, old|
          old.each_line do |line|
            if line.start_with?('#')
              new.write(line)
              next
            end

            fs, mountpoint = line.split

            if fs == 'none'
              if mountpoint == '/dev/pts'
                has_pts = true
              elsif mountpoint == '/dev/shm'
                has_shm = true
              end
            end

            new.write(line)
          end

          unless has_pts
            new.puts 'none    /dev/pts        devpts  rw,gid=5,mode=620       0       0'
          end

          unless has_shm
            new.puts 'none    /dev/shm        tmpfs   defaults                0       0'
          end
        end
      end

      # Remove upstart service on centos < 7
      init = File.join(@rootfs, 'etc/init')
      shutdown = File.join(init, 'shutdown.conf')

      File.unlink(shutdown) if File.exist?(shutdown)

      # Patch/create tty services for centos < 7
      if Dir.exist?(init)
        regenerate_file(File.join(init, 'console.conf'), 0644) do |new, old|
          if old
            old.each_line do |line|
              if /^#{Regexp.escape('exec /sbin/agetty')}/ =~ line
                new.puts('exec /sbin/mingetty console')
              else
                new.write(line)
              end
            end

          else
            new.puts(<<END
start on stopped rc RUNLEVEL=[2345]
stop on runlevel [!2345]
respawn
exec /sbin/mingetty console
END
            )
          end
        end
      end
    end

    def convert_devuan
      inittab = File.join(@rootfs, 'etc/inittab')

      if File.exist?(inittab)
        regenerate_file(inittab, 0644) do |new, old|
          old.each_line do |line|
            if line =~ /^#{Regexp.escape('pf::powerwait:/sbin/halt')}/
              new.puts('pf::powerwait:/etc/init.d/powerfail start')
            elsif line.start_with?('# Start getty on /dev/console')
              next
            elsif lie.start_with?('c0:2345:respawn:/sbin/agetty --noreset 38400 console')
              next
            else
              new.write(line)
            end
          end
        end
      end
    end

    def convert_gentoo
      inittab = File.join(@rootfs, 'etc/inittab')

      if File.exist?(inittab)
        to_remove = [
          '# Start getty on /dev/console',
          'c0:2345:respawn:/sbin/agetty --noreset 38400 console',
          '# Clean container shutdown on SIGPWR',
          'pf:12345:powerwait:/sbin/halt',
        ]

        regenerate_file(inittab, 0644) do |new, old|
          old.each_line do |line|
            next if to_remove.detect { |v| line.start_with?(v) }
            new.write(line)
          end

          new.puts('c0:2345:respawn:/sbin/agetty --noreset 38400 tty0')
        end
      end

      regenerate_file(File.join(@rootfs, 'etc/rc.conf'), 0644) do |new, old|
        if old.nil?
          new.puts('rc_sys="openvz"')
        else
          old.each_line do |line|
            if line =~ /^rc_sys=/
              new.puts('rc_sys="openvz"')
            else
              new.write(line)
            end
          end
        end
      end
    end

    def convert_opensuse
      raise NotImplementedError
    end

    def convert_ubuntu
      fstab = File.join(@rootfs, 'lib/init/fstab')

      if File.exist?(fstab)
        to_remove = [
          "# The following entry was commented by vpsAdmin when migrating",
          "# to vpsAdminOS. Do not uncomment while running on vpsAdminOS.",
        ]

        regenerate_file(fstab, 0644) do |new, old|
          old.each_line do |line|
            if to_remove.detect { |v| line.start_with?(v) }
              next

            elsif /^\s*#\s*none\s+#{Regexp.escape('/proc/sys/fs/binfmt_misc')}/ =~ line
              new.puts('none            /proc/sys/fs/binfmt_misc  binfmt_misc     nodev,noexec,nosuid,optional                 0 0')

            else
              new.write(line)
            end
          end
        end
      end
    end

    def convert_redhat
      add_systemd_overrides
    end

    alias_method :convert_fedora, :convert_redhat

    def add_systemd_overrides
      %w(systemd-journald systemd-logind).each do |sv|
        dir = File.join(@rootfs, 'etc/systemd/system', "#{sv}.service.d")
        FileUtils.mkpath(dir) unless Dir.exist?(dir)

        File.open(File.join(dir, 'override.conf'), 'a') do |f|
          f.puts('[Service]')
          f.puts('SystemCallFilter=')
          f.puts('MemoryDenyWriteExecute=no')
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
