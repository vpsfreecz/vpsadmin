require 'pathname'
$: << File.dirname(Pathname.new(__FILE__).realpath + '../../')

require 'optparse'
require 'rubygems'
require 'daemons'
require 'require_all'
require 'eventmachine'
require 'json'
require 'yaml'
require 'mysql'

if RUBY_VERSION >= '2.0'
  require 'pry-remote'
  require 'mail'
end

module VpsAdmind
  STANDALONE = false unless const_defined?(:STANDALONE)

  module SystemProbe ; end
end

require_rel 'vpsadmind/utils.rb'
require_rel 'vpsadmind/*.rb'
require_rel 'vpsadmind/console'
require_rel 'vpsadmind/commands/base'
require_rel 'vpsadmind/commands'
require_rel 'vpsadmind/remote_commands/base'
require_rel 'vpsadmind/remote_commands/'
require_rel 'vpsadmind/firewall/'
require_rel 'vpsadmind/system_probes'
