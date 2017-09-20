require 'bundler/setup'
require_relative 'lib/vpsadmin'

run VpsAdmin::API.default.app
