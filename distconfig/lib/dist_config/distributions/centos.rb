require 'dist_config/distributions/redhat'

module DistConfig
  class Distributions::CentOS < Distributions::RedHat
    distribution :centos

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
