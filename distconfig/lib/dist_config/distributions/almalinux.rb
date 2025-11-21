require 'dist_config/distributions/redhat'

module DistConfig
  class Distributions::AlmaLinux < Distributions::RedHat
    distribution :almalinux

    class Configurator < Distributions::RedHat::Configurator
      def install_user_script(content)
        us = UserScript.new(vps_config, content)
        us.install_systemd
        us.write_script
      end

      protected

      def network_class
        [
          Network::NetworkManager,
          Network::RedHatNetworkManager,
          Network::RedHatInitScripts
        ]
      end
    end
  end
end
