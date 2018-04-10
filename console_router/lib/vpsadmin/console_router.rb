require 'sinatra/base'
require 'eventmachine'
require 'base64'
require '/opt/vpsadmin/vpsadmind/lib/vpsadmind/standalone'

module VpsAdmin
  module ConsoleRouter
  end
end

require_relative 'console_router/console'
require_relative 'console_router/router'
require_relative 'console_router/server'
