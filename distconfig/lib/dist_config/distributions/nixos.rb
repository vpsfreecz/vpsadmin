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

    def bin_path
      # TODO: this might not work with impermanence
      with_rootfs do
        File.realpath('/nix/var/nix/profiles/system/sw/bin')
      rescue Errno::ENOENT
        '/bin'
      end
    end
  end
end
