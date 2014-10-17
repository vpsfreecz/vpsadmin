require 'rubygems'
require 'require_all'
require 'eventmachine'
require 'json'
require 'yaml'
require 'mysql'

module VpsAdmind

end

require_rel 'vpsadmind/utils.rb'
require_rel 'vpsadmind/*.rb'
require_rel 'vpsadmind/commands/base'
require_rel 'vpsadmind/commands'
