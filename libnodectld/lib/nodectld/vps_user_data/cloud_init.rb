require_relative 'base'

module NodeCtld
  module VpsUserData
    class CloudInit < Base
      def deploy
        install_cloud_init
        fork_chroot_wait { add_user_data }
      end

      protected

      def install_cloud_init
        tmp = Tempfile.new('install-cloud-init')
        tmp.puts(<<~END)
          #!/bin/sh
          set -e
          #{install_command}
          #{enable_command}
        END
        tmp.close

        osctl(
          %i[ct runscript],
          [@vps_id, tmp.path],
          {
            run_container: true,
            network: true
          }
        )

        tmp.unlink
      end

      def add_user_data
        nocloud = '/var/lib/cloud/seed/nocloud'

        FileUtils.mkdir_p(nocloud, mode: 0o700)

        File.open(File.join(nocloud, 'meta-data'), 'w') do |f|
          f.puts("instance-id: #{@vps_id}")
        end

        File.open(File.join(nocloud, 'network-config'), 'w') do |f|
          f.puts(<<~END)
            network:
              version: 2
              ethernets: {}
          END
        end

        user_data = File.join(nocloud, 'user-data')

        File.open(user_data, 'w') do |f|
          f.puts(@content)
        end

        # Disable network configuration, so that cloud-init doesn't break
        # already existing network configuration. vendor-data doesn't seem to work,
        # so putting it to /etc.
        cloud_d = '/etc/cloud/cloud.cfg.d'

        FileUtils.mkdir_p(cloud_d)

        File.open(File.join(cloud_d, '99-disable-network-config.cfg'), 'w') do |f|
          f.puts('network: {config: disabled}')
        end

        return unless @format == 'cloudinit_script'

        File.chmod(0o755, user_data)
      end

      def install_command
        case @os_template['distribution']
        when 'almalinux', 'centos', 'fedora', 'rocky'
          'dnf install -y cloud-init'
        when 'alpine'
          'apk add cloud-init'
        when 'arch'
          'pacman -Sy --noconfirm cloud-init'
        when 'debian', 'ubuntu'
          'apt-get install -y cloud-init'
        when 'opensuse'
          'zypper install -y cloud-init'
        when 'gentoo'
          'emerge -q app-emulation/cloud-init'
        end
      end

      def enable_command
        systemd = %w[
          cloud-config
          cloud-final
          cloud-init-local
          cloud-init-main
          cloud-init-network
          cloud-init
        ].map { |v| "systemctl enable #{v}.service || true" }.join("\n")

        case @os_template['distribution']
        when 'almalinux', 'arch', 'centos', 'fedora', 'opensuse', 'rocky'
          systemd
        when 'debian', 'ubuntu'
          ':'
        when 'alpine'
          'setup-cloud-init'
        when 'gentoo'
          if @os_template['version'].start_with?('systemd-')
            systemd
          else
            [
              'rc-update add cloud-init-local boot',
              'rc-update add cloud-config default',
              'rc-update add cloud-final default',
              'rc-update add cloud-init default'
            ].join("\n")
          end
        end
      end
    end
  end
end
