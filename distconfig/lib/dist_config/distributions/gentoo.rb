require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Gentoo < Distributions::Base
    distribution :gentoo

    class Configurator < DistConfig::Configurator
      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'conf.d', 'hostname')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts('# Set to the hostname of this machine')
            f.puts("hostname=\"#{new_hostname}\"")
          end
        end
      end

      protected

      def network_class
        [
          Network::Netifrc,
          Network::SystemdNetworkd
        ]
      end
    end

    def apply_hostname
      ct_syscmd(['hostname', ct.hostname.local])
    rescue SystemCommandFailed => e
      log(:warn, "Unable to apply hostname: #{e.message}")
    end
  end
end
