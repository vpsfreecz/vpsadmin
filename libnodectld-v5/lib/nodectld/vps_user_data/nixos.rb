require 'fileutils'
require_relative 'base'

module NodeCtld
  module VpsUserData
    class Nixos < Base
      def deploy
        files = {
          'nixos_configuration' => 'configuration.nix',
          'nixos_flake_configuration' => 'flake.nix'
        }

        file = files[@format]
        return if file.nil?

        fork_chroot_wait do
          FileUtils.mkdir_p(nixos_dir)
          File.write(File.join(nixos_dir, file), @content)
        end
      end

      def apply
        wait_for_system_running

        tmp = Tempfile.new('nixos-rebuild')
        tmp.puts(<<~END)
          #!/bin/sh

          . /etc/profile

          #{nixos_rebuild} 2>&1 | tee /var/log/vpsadmin-nixos-output.log

        END
        tmp.close

        osctl(%i[ct runscript], [@vps_id, tmp.path])

        tmp.unlink
      end

      protected

      def wait_for_system_running
        3.times do
          begin
            out = osctl(%i[ct exec], [@vps_id, 'systemctl', 'is-system-running', '--wait']).output
            return if out.strip == 'running'
          rescue SystemCommandFailed
            # pass
          end

          sleep(10)
        end
      end

      def nixos_rebuild
        case @format
        when 'nixos_configuration'
          "NIXOS_CONFIG=#{File.join(nixos_dir, 'configuration.nix')} nixos-rebuild switch"

        when 'nixos_flake_configuration'
          "nixos-rebuild switch --flake #{File.join(nixos_dir)}#vps"

        when 'nixos_flake_uri'
          "nixos-rebuild switch --flake \"#{@content.strip}\""
        end
      end

      def nixos_dir
        '/etc/vpsadmin-nixos'
      end
    end
  end
end
