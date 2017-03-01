class OutageVps < ActiveRecord::Base
  belongs_to :outage
  belongs_to :vps
end

class Vps
  has_many :outage_vpses
end
