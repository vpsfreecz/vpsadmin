require 'dist_config/distributions/debian'

module DistConfig
  class Distributions::Devuan < Distributions::Debian
    distribution :devuan
  end
end
