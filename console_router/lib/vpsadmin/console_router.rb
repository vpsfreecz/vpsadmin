require 'base64'
require 'require_all'
require 'sinatra/base'

module VpsAdmin
  module ConsoleRouter
  end
end

require_rel 'console_router/*.rb'
