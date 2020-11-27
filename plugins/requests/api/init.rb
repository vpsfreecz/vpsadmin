module VpsAdmin::API::Plugins
  module Requests
    module TransactionChains ; end
  end
end

require_rel 'models'
require_rel 'resources/user_request'
require_rel 'resources/base'
require_rel 'resources/registration'
require_rel 'resources/change'
require_rel 'resources/override'
require_rel 'lib'

if defined?(namespace)
  # Load tasks only if run by rake
  load_rel 'tasks/*.rake'
end
