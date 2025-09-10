require 'dist_config/distributions/redhat'

module DistConfig
  class Distributions::Fedora < Distributions::RedHat
    distribution :fedora

    class Configurator < Distributions::RedHat::Configurator
      protected

      def network_class
        [
          Network::NetworkManager,
          Network::RedHatNetworkManager,
          Network::SystemdNetworkd,
          Network::RedHatInitScripts
        ]
      end
    end
  end
end
