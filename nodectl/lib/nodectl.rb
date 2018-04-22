require 'require_all'

module NodeCtl
  module Commands ; end
  module CommandTemplates ; end
end

require_rel 'nodectl/*.rb'
require_rel 'nodectl/command'
require_rel 'nodectl/command_templates'
require_rel 'nodectl/commands'
