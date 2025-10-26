require 'dist_config/distributions/base'
require 'dist_config/helpers/redhat'

module DistConfig
  class Distributions::RedHat < Distributions::Base
    class Configurator < DistConfig::Configurator
      include DistConfig::Helpers::RedHat

      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'hostname')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts(new_hostname.local)
          end
        end

        # /etc/sysconfig/network for older systems
        set_params(
          File.join(rootfs, 'etc', 'sysconfig', 'network'),
          { 'HOSTNAME' => new_hostname.local }
        )
      end
    end

    def apply_hostname
      ct_syscmd(['hostname', ct.hostname.fqdn])
    rescue SystemCommandFailed => e
      log(:warn, "Unable to apply hostname: #{e.message}")
    end
  end
end
