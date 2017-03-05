class OutageVps < ActiveRecord::Base
  belongs_to :outage
  belongs_to :vps
  belongs_to :user
  belongs_to :environment
  belongs_to :location
  belongs_to :node
end

class Vps
  has_many :outage_vpses
end
