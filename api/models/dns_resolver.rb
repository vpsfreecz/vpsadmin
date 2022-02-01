require_relative 'lockable'

class DnsResolver < ActiveRecord::Base
  belongs_to :location
  has_many :vpses

  alias_attribute :addr, :addrs

  include Lockable

  validates :addrs, :label, presence: true
  validate :universal_or_location

  def self.pick_suitable_resolver_for_vps(vps, except: [])
    first_ip = vps.ip_addresses
      .joins(:network)
      .group('networks.ip_version')
      .order('networks.ip_version')
      .take
    ip_v = first_ip ? first_ip.network.ip_version : 4

    self.where(
      'dns_resolvers.location_id = ? OR is_universal = 1',
      vps.node.location.id
    ).where(
      'ip_version = ? OR ip_version IS NULL', ip_v
    ).where.not(id: except).order(:is_universal).take
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
    if (is_universal && location_id) || (!is_universal && !location_id)
      errors.add(:is_universal, 'must be either universal or location specific')
    end
  end

  def available_to_vps?(vps)
    is_universal || location_id == vps.node.location.id
  end
end
