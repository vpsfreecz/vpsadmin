require 'vpsadmin/api/lifetimes'

class DefaultLifetimeValue < ApplicationRecord
  belongs_to :environment

  enum :direction, %i[leave enter]
  enum :state, VpsAdmin::API::Lifetimes::STATES
end
