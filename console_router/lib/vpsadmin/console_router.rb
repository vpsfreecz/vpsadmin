require 'active_record'
require 'base64'
require 'eventmachine'
require 'require_all'
require 'sinatra/base'
require 'sinatra/activerecord'

module VpsAdmin
  module ConsoleRouter
  end
end

require_rel '../../models'
require_rel 'console_router/*.rb'
