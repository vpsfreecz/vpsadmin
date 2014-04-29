class IpAddress < ActiveRecord::Base
  self.table_name = 'vps_ip'
  self.primary_key = 'ip_id'

  belongs_to :location, :foreign_key => :ip_location
  belongs_to :vps, :foreign_key => :vps_id
  has_paper_trail
end
