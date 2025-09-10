require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Debian < Distributions::Base
    distribution :debian

    class Configurator < DistConfig::Configurator
      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'hostname')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts(new_hostname.local)
          end
        end
      end

      def network_class
        Network::Ifupdown
      end
    end

    def apply_hostname
      ct_syscmd(%w[hostname -F /etc/hostname])
    rescue SystemCommandFailed => e
      log(:warn, "Unable to apply hostname: #{e.message}")
    end
  end
end
