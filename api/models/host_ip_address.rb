class HostIpAddress < ApplicationRecord
  belongs_to :ip_address
  has_many :routed_via_addresses,
           class_name: 'IpAddress', foreign_key: :route_via_id
  belongs_to :reverse_dns_record, class_name: 'DnsRecord'
  has_many :dns_zone_transfers

  include Lockable

  # All child writers share the parent lock with IP assignment and release.
  def lock_with_ip!(chain, actor: nil)
    ip = ::IpAddress.find(ip_address_id)
    chain.lock(ip)
    ip.reload(lock: true)
    chain.lock(self)
    reload(lock: true)
    self.ip_address = ip
    ip.ensure_owner!(actor) if actor
  end

  # Call with the host and parent locked, before clearing the parent's owner.
  def remove_dns_transfers!(chain)
    dns_zone_transfers.existing.order(:id).lock.each do |transfer|
      chain.use_chain(TransactionChains::DnsZoneTransfer::Destroy, args: [transfer])
    end
  end

  def assigned?
    !order.nil?
  end

  alias assigned assigned?

  def version
    ip_address.network.ip_version
  end

  # @return [::User, nil]
  def current_owner
    ip_address.current_owner
  end

  def reverse_record_value
    reverse_dns_record&.content
  end

  def reverse_record_domain
    ip = IPAddress.parse(ip_addr)

    case ip_address.network.ip_version
    when 4
      "#{ip.octets.reverse.join('.')}.in-addr.arpa."
    when 6
      "#{ip.address.split(':').map(&:chars).flatten.reverse.join('.')}.ip6.arpa."
    end
  end
end
