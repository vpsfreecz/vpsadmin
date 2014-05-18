class DnsResolver < ActiveRecord::Base
  self.table_name = 'cfg_dns'
  self.primary_key = 'dns_id'

  belongs_to :location, foreign_key: :dns_location
  has_many :vpses

  validates :dns_ip, :dns_label, presence: true

  alias_attribute :addr, :dns_ip

  def self.pick_suitable_resolver_for_vps(vps)
    self.where(
      'dns_location = ? OR dns_is_universal = 1',
      vps.node.location.id
    ).order(:dns_is_universal).take
  end
end
