class DnsResolver < ActiveRecord::Base
  self.table_name = 'cfg_dns'
  self.primary_key = 'dns_id'

  belongs_to :location, foreign_key: :dns_location
  has_many :vpses

  validates :dns_ip, :dns_label, presence: true
  validate :universal_or_location

  alias_attribute :addr, :dns_ip

  include Lockable

  def self.pick_suitable_resolver_for_vps(vps, except: [])
    self.where(
      'dns_location = ? OR dns_is_universal = 1',
      vps.node.location.id
    ).where.not(dns_id: except).order(:dns_is_universal).take
  end

  def update(attrs)
    TransactionChains::DnsResolver::Update.fire(self, attrs)
  end

  def universal_or_location
    if (dns_is_universal && dns_location) || (!dns_is_universal && !dns_location)
      errors.add(:dns_is_universal, 'must be either universal or location specific')
    end
  end
end
