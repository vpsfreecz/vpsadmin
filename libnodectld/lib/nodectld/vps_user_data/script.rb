require 'fileutils'
require_relative 'base'

module NodeCtld
  module VpsUserData
    class Script < Base
      def deploy
        @dir = '/usr/local/vpsadmin-script'
        @wrapper = File.join(@dir, 'wrapper.sh')
        @user_script = File.join(@dir, 'user-script')
        @cleanup = []

        fork_chroot_wait do
          install_script
          write_script
        end
      end

      protected

      def write_script
        FileUtils.mkdir_p(@dir)

        File.open(@wrapper, 'w', 0o755) do |f|
          f.puts(<<~END)
            #!/bin/sh
            # This script has been installed by vpsAdmin

            export VPSADMIN_VPS_ID=#{@vps_id}

            mkdir -p /var/log
            #{@user_script} 2>&1 | tee /var/log/vpsadmin-script-output.log

            rm -rf "#{@dir}" #{@cleanup.map { |v| "\"#{v}\"" }.join(' ')}
          END
        end

        File.open(@user_script, 'w', 0o755) do |f|
          f.write(@content)
        end
      end

      def install_script
        case @os_template['distribution']
        when 'almalinux', 'arch', 'centos', 'debian', 'fedora', 'opensuse', 'rocky', 'ubuntu'
          install_systemd
        when 'alpine'
          install_openrc
        when 'devuan'
          install_sysvinit
        when 'gentoo'
          if @os_template['version'].start_with?('systemd-')
            install_systemd
          else
            install_openrc
          end
        when 'void'
          install_runit
        end
      end

      def install_systemd
        service = 'vpsadmin-script.service'
        path = File.join('/etc/systemd/system', service)

        File.open(path, 'w') do |f|
          f.puts(<<~END)
            [Unit]
            Description=vpsAdmin user script
            After=multi-user.target
            Wants=network-online.target

            [Service]
            Type=oneshot
            ExecStart=#{@wrapper}
            RemainAfterExit=no

            [Install]
            WantedBy=multi-user.target
          END
        end

        link = File.join('/etc/systemd/system/multi-user.target.wants', service)
        replace_symlink(path, link)

        @cleanup << path << link
      end

      def install_openrc
        service = 'vpsadmin-script'
        path = File.join('/etc/init.d', service)

        File.open(path, 'w', 0o755) do |f|
          f.puts(<<~END)
            #!/sbin/openrc-run

            description="vpsAdmin user script"

            depend() {
              after localmount
              need net
            }

            start() {
              #{wrapper}
              eend $?
            }
          END
        end

        link = File.join('/etc/runlevels/default', service)
        replace_symlink(path, link)

        @cleanup << path << link
      end

      def install_runit
        service = 'vpsadmin-script'
        path = File.join('/etc/sv', service)
        run_file = File.join(path, 'run')

        FileUtils.mkdir_p(path)

        File.open(run_file, 'w', 0o755) do |f|
          f.puts(<<~END)
            #!/bin/sh
            exec #{wrapper}
          END
        end

        link = File.join('/var/service', service)
        replace_symlink(path, link)

        @cleanup << path << link
      end

      def install_sysvinit
        service = 'vpsadmin-script'
        path = File.join('/etc/init.d', service)

        File.open(path, 'w', 0o755) do |f|
          f.puts(<<~END)
            #!/bin/sh
            ### BEGIN INIT INFO
            # Provides:          vpsadmin-script
            # Required-Start:    $remote_fs $network
            # Required-Stop:
            # Default-Start:     2 3 4 5
            # Default-Stop:
            # Short-Description: Run vpsAdmin user script
            ### END INIT INFO

            case "$1" in
              start)
                exec #{wrapper}
                ;;
              *)
                echo "Usage: $0 {start}"
                exit 1
                ;;
            esac
          END
        end

        runlevels = (2..5).each do |v|
          link = "/etc/rc#{v}.d/S99#{service}"
          replace_symlink(path, link)
          @cleanup << link
        end

        @cleanup << path
      end

      def replace_symlink(path, link)
        File.symlink(path, link)
      rescue Errno::EEXIST
        File.unlink(link)
        File.symlink(path, link)
      end
    end
  end
end
