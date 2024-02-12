require 'require_all'
require 'active_record'
require 'paper_trail'
require 'haveapi'
require 'ancestry'
require 'ipaddress'
require 'digest/sha1'

Thread.abort_on_exception = true

path = __dir__
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

VpsAdmin::API.load_configurable(:api)
VpsAdmin::API.load_configurable(:hooks)
VpsAdmin::API.load_configurable(:dataset_plans)
VpsAdmin::API.load_configurable(:incident_reports)

require_rel 'vpsadmin/api/resources'
require_rel 'vpsadmin/api/operations'

require_rel 'vpsadmin/supervisor/*.rb'
require_rel 'vpsadmin/supervisor/console/*.rb'
require_rel 'vpsadmin/supervisor/node/*.rb'
