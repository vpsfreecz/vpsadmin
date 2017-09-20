module VpsAdmin::API::Plugins
  module Payments
    module TransactionChains ; end
    module Backends ; end
  end
end

require_rel 'lib'
require_rel 'models'
require_rel 'resources'

if defined?(namespace)
  # Load tasks only if run by rake
  load_rel 'tasks/*.rake'
end
