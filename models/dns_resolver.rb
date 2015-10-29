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
    first_ip = vps.ip_addresses.group(:ip_v).order(:ip_v).take
    ip_v = first_ip ? first_ip.ip_v : 4

    self.where(
      'dns_location = ? OR dns_is_universal = 1',
      vps.node.location.id
    ).where(
        'ip_version = ? OR ip_version IS NULL', ip_v
    ).where.not(dns_id: except).order(:dns_is_universal).take
  end

  def update(attrs)
    TransactionChains::DnsResolver::Update.fire(self, attrs)
  end

  def delete
    TransactionChains::DnsResolver::Destroy.fire(self)
  end

  def in_use?
    ::Vps.including_deleted.exists?(dns_resolver: self)
  end

  def universal_or_location
    if (dns_is_universal && dns_location) || (!dns_is_universal && !dns_location)
      errors.add(:dns_is_universal, 'must be either universal or location specific')
    end
  end
end
