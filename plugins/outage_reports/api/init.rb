module VpsAdmin::API::Plugins
  module OutageReports
    module TransactionChains; end
  end
end

require_rel 'lib'
require_rel 'models'
require_rel 'resources'

if defined?(namespace)
  # Load tasks only if run by rake
  load_rel 'tasks/*.rake'
end

VpsAdmin::API::Metrics.register_plugin(VpsAdmin::API::Plugins::OutageReports::Metrics)
