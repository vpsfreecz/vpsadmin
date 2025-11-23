require 'dist_config/distributions/base'

module DistConfig
  class Distributions::NixOS < Distributions::Base
    distribution :nixos

    class Configurator < DistConfig::Configurator
      def network(netifs)
        tpl_base = 'network/nixos'

        %w[add del].each do |operation|
          cmds = netifs.map do |netif|
            ErbTemplate.render(
              File.join(tpl_base, netif.type.to_s),
              { netif:, op: operation }
            )
          end

          writable?(File.join(rootfs, "ifcfg.#{operation}")) do |path|
            File.write(path, cmds.join("\n"))
          end
        end
      end

      protected

      def network_class
        nil
      end
    end

    def post_mount(opts)
      # TODO: support for NixOS impermanence was here
    end

    def set_hostname(*_)
      log(:warn, 'Unable to apply hostname to NixOS container')
    end

    def update_etc_hosts(**_)
      # not supported
    end

    def unset_etc_hosts
      # not supported
    end

    def set_dns_resolvers(*_)
      super if ct.impermanence.nil? || ct.running?
    end

    def apply_nixos_config(format, content)
      files = {
        'nixos_configuration' => 'configuration.nix',
        'nixos_flake_configuration' => 'flake.nix'
      }

      file = files[format]

      if file
        with_rootfs do
          FileUtils.mkdir_p(nixos_config_dir)
          File.write(File.join(nixos_config_dir, file), content)
        end
      end

      wair_for_systemctl_running

      script = <<~END
        . /etc/profile
        #{nixos_rebuild_command(format, content)} 2>&1 | tee /var/log/vpsadmin-nixos-output.log
      END

      ct_syscmd(['sh'], stdin: script)

      nil
    end

    def bin_path
      # TODO: this might not work with impermanence
      with_rootfs do
        File.realpath('/nix/var/nix/profiles/system/sw/bin')
      rescue Errno::ENOENT
        '/bin'
      end
    end

    protected

    def wait_for_systemctl_running
      3.times do
        begin
          out = ct_syscmd(['systemctl', 'is-system-running', '--wait']).output
          return if out.strip == 'running'
        rescue SystemCommandFailed
          # pass
        end

        sleep(10)
      end
    end

    def nixos_rebuild_command(format, content)
      case format
      when 'nixos_configuration'
        "NIXOS_CONFIG=#{File.join(nixos_config_dir, 'configuration.nix')} nixos-rebuild switch"

      when 'nixos_flake_configuration'
        "nixos-rebuild switch --flake #{File.join(nixos_config_dir)}#vps"

      when 'nixos_flake_uri'
        "nixos-rebuild switch --flake \"#{content.strip}\""
      end
    end

    def nixos_config_dir
      '/etc/vpsadmin-nixos'
    end
  end
end
