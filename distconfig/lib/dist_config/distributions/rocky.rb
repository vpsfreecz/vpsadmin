require 'dist_config/distributions/redhat'

module DistConfig
  class Distributions::Rocky < Distributions::RedHat
    distribution :rocky

    class Configurator < Distributions::RedHat::Configurator
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
