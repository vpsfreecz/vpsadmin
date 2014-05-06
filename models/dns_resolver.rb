class DnsResolver < ActiveRecord::Base
  self.table_name = 'cfg_dns'
  self.primary_key = 'dns_id'

  belongs_to :location, foreign_key: :dns_location
end
