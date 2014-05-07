require 'require_all'
require 'active_record'
require 'paper_trail'
require 'sinatra/base'
require 'sinatra/activerecord'
require 'pp'

module VpsAdmin
  module API
    module Resources

    end

    module Actions

    end
  end
end

require_rel 'api/crypto_provider'
require_rel '../../models'
require_rel 'api'
