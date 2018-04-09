require 'pathname'
$: << File.dirname(Pathname.new(__FILE__).realpath + '../../')

require 'require_all'

module NodeCtld
  STANDALONE = false unless const_defined?(:STANDALONE)

  module Firewall ; end
end

require_relative 'nodectld/utils'
require_rel 'nodectld/firewall/main'
require_rel 'nodectld/*.rb'
require_rel 'nodectld/console'
require_rel 'nodectld/commands/base'
require_rel 'nodectld/commands'
require_rel 'nodectld/remote_commands/base'
require_rel 'nodectld/remote_commands/'
require_rel 'nodectld/firewall/'
require_relative 'nodectld/system_probes'
