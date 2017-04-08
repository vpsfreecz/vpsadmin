require_rel 'lib'
require_rel 'models'
load_rel 'tasks/*.rake'

VpsAdmin::API.load_configurable(:policies)
