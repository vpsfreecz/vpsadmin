require 'require_all'
require 'active_record'
require 'composite_primary_keys'
require 'paper_trail'
require 'pp'
require 'haveapi'
require 'ancestry'
require 'ipaddress'
require 'digest/sha1'

Thread.abort_on_exception = true

path = File.dirname(__FILE__)
$: << path unless $:.include?(path)

module VpsAdmin
  module API
    module Resources

    end

    module Actions

    end
  end
end

require_relative 'vpsadmin/scheduler'
require_relative 'vpsadmin/api/crypto_providers'
require_relative 'vpsadmin/api/maintainable'
require_relative 'vpsadmin/api/dataset_properties'
require_rel 'vpsadmin/*.rb'
require_rel 'vpsadmin/api/*.rb'
require_rel 'vpsadmin/api/authentication'
require_rel 'vpsadmin/api/plugin'

VpsAdmin::API.load_configurable(:dataset_properties)

require_rel '../models/transaction.rb'
require_rel '../models/transactions/'
require_rel '../models/transaction_chain.rb'
require_rel '../models/transaction_chains/'
require_rel '../models/*.rb'

# Customize the API server before it is mounted.
# @yieldparam [HaveAPI::Server]
def api(*args, &block)
  VpsAdmin::API.configure(*args, &block)
end

VpsAdmin::API.load_configurable(:api)
VpsAdmin::API.load_configurable(:hooks)
VpsAdmin::API.load_configurable(:dataset_plans)

require_rel 'vpsadmin/api/resources'
require_rel 'vpsadmin/api/operations'
