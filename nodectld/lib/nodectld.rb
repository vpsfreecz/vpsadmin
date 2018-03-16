require 'pathname'
$: << File.dirname(Pathname.new(__FILE__).realpath + '../../')

require 'optparse'
require 'require_all'
require 'eventmachine'
require 'json'
require 'yaml'
require 'mysql'
require 'pry-remote'
require 'mail'
require 'libosctl'

module NodeCtld
  STANDALONE = false unless const_defined?(:STANDALONE)

  module Firewall ; end
  module SystemProbe ; end
end

require_rel 'nodectld/utils.rb'
require_rel 'nodectld/firewall/main'
require_rel 'nodectld/*.rb'
require_rel 'nodectld/console'
require_rel 'nodectld/commands/base'
require_rel 'nodectld/commands'
require_rel 'nodectld/remote_commands/base'
require_rel 'nodectld/remote_commands/'
require_rel 'nodectld/firewall/'
require_rel 'nodectld/system_probes'
