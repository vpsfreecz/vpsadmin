require 'vpsadmin/api/lifetimes'

class DefaultLifetimeValue < ActiveRecord::Base
  belongs_to :environment

  enum direction: %i(leave enter)
  enum state: VpsAdmin::API::Lifetimes::STATES
end
