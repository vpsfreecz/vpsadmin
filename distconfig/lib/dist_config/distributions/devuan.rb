require 'dist_config/distributions/debian'

module DistConfig
  class Distributions::Devuan < Distributions::Debian
    distribution :devuan

    class Configurator < Distributions::Debian::Configurator
      def install_user_script(content)
        us = UserScript.new(vps_config, content)
        us.install_sysvinit
        us.write_script
      end
    end
  end
end
