require 'dist_config/distributions/base'

module DistConfig
  class Distributions::OpenSuse < Distributions::Base
    distribution :opensuse

    class Configurator < DistConfig::Configurator
      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'hostname')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts(new_hostname.local)
          end
        end
      end

      protected

      def network_class
        Network::SuseSysconfig
      end
    end

    def apply_hostname
      ct_syscmd(['hostname', ct.hostname.fqdn])
    rescue SystemCommandFailed => e
      log(:warn, "Unable to apply hostname: #{e.message}")
    end
  end
end
