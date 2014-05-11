class DnsResolver < ActiveRecord::Base
  self.table_name = 'cfg_dns'
  self.primary_key = 'dns_id'

  belongs_to :location, foreign_key: :dns_location
  has_many :vpses

  validates :dns_ip, :dns_label, presence: true

  alias_attribute :addr, :dns_ip
end
