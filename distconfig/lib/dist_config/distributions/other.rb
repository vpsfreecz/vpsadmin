require 'dist_config/distributions/base'

module DistConfig
  class Distributions::Other < Distributions::Base
    distribution :other

    def configurator_class
      DistConfig::Configurator
    end

    def set_hostname(_opts = {})
      log(
        :warn,
        ct,
        "Unable to set hostname: #{vps_config.distribution} not supported"
      )
    end

    def network(_opts = {})
      log(
        :warn,
        ct,
        "Unable to configure network: #{vps_config.distribution} not supported"
      )
    end
  end
end
