require 'dist_config/distributions/debian'

module DistConfig
  class Distributions::Alpine < Distributions::Debian
    distribution :alpine
  end
end
