class SecurityAdvisoryVps < ApplicationRecord
  belongs_to :security_advisory
  belongs_to :vps
  belongs_to :user
  belongs_to :environment
  belongs_to :location
  belongs_to :node

  enum :node_state, ::SecurityAdvisoryNodeStatus.states, prefix: :node

  validates :security_advisory,
            :vps,
            :user,
            :environment,
            :location,
            :node,
            presence: true
end

class Vps
  has_many :security_advisory_vpses
end
