require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Alpine < Distributions::Base
    distribution :alpine

    class Configurator < DistConfig::Configurator
      def set_hostname(new_hostname, old_hostname: nil)
        # /etc/hostname
        writable?(File.join(rootfs, 'etc', 'hostname')) do |path|
          regenerate_file(path, 0o644) do |f|
            f.puts(new_hostname.local)
          end
        end
      end

      def install_user_script(content)
        us = UserScript.new(vps_config, content)
        us.install_openrc
        us.write_script
      end

      def network_class
        Network::Ifupdown
      end
    end

    def install_cloud_init_commands
      [CloudInit.install_apkv2, CloudInit.enable_alpine]
    end
  end
end
