require 'rubygems'
require 'require_all'
require 'eventmachine'
require 'json'
require 'yaml'
require 'mysql'

if RUBY_VERSION >= '2.0'
  require 'pry-remote'
end

module VpsAdmind

end

require_rel 'vpsadmind/utils.rb'
require_rel 'vpsadmind/*.rb'
require_rel 'vpsadmind/commands/base'
require_rel 'vpsadmind/commands'
require_rel 'vpsadmind/remote_commands/base'
require_rel 'vpsadmind/remote_commands/'
