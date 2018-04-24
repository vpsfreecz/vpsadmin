require 'require_all'

module NodeCtld
  STANDALONE = false unless const_defined?(:STANDALONE)

  module Firewall ; end

  def self.root
    File.join(File.dirname(__FILE__), '..')
  end
end

require 'nodectld/utils'
require_rel 'nodectld/firewall/main'
require_rel 'nodectld/*.rb'
require_rel 'nodectld/console'
require_rel 'nodectld/commands/base'
require_rel 'nodectld/commands'
require_rel 'nodectld/remote_commands/base'
require_rel 'nodectld/remote_commands/'
require_rel 'nodectld/firewall/'
require 'nodectld/system_probes'
