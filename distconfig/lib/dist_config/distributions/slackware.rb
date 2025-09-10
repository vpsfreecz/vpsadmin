require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Slackware < Distributions::Base
    distribution :slackware

    class Configurator < DistConfig::Configurator
      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'HOSTNAME')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts(new_hostname.local)
          end
        end
      end

      def network(netifs)
        tpl_base = 'network/slackware'

        { start: 'add', stop: 'del' }.each do |operation, cmd|
          cmds = netifs.map do |netif|
            ErbTemplate.render(
              File.join(tpl_base, netif.type.to_s),
              { netif:, cmd: }
            )
          end

          writable?(File.join(rootfs, 'etc/rc.d', "rc.venet.#{operation}")) do |path|
            File.write(path, cmds.join("\n"))
          end
        end
      end

      protected

      def network_class
        nil
      end
    end

    def apply_hostname
      ct_syscmd(%w[hostname -F /etc/HOSTNAME])
    rescue SystemCommandFailed => e
      log(:warn, "Unable to apply hostname: #{e.message}")
    end
  end
end
