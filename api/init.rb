require_rel 'lib'
require_rel 'models'

if defined?(namespace)
  # Load tasks only if run by rake
  load_rel 'tasks/*.rake'
end

VpsAdmin::API.load_configurable(:monitoring)
