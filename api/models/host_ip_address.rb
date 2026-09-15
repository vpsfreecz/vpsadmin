class HostIpAddress < ApplicationRecord
  belongs_to :ip_address
  has_many :routed_via_addresses,
           class_name: 'IpAddress', foreign_key: :route_via_id
  belongs_to :reverse_dns_record, class_name: 'DnsRecord'
  has_many :dns_zone_transfers

  include Lockable

  # Reserve every parent before any child when an operation touches a set.
  def self.lock_all_with_ips!(chain, hosts, actor: nil)
    parents = ::IpAddress.where(id: hosts.map(&:ip_address_id)).to_a
    ::IpAddress.lock_all_current!(chain, parents)
    hosts.sort_by { |host| [host.ip_address_id, host.id] }.each do |host|
      host.lock_with_ip!(chain, actor:)
    end
  end

  # All child writers share the parent lock with IP assignment and release.
  def lock_with_ip!(chain, actor: nil)
    ip = ::IpAddress.find(ip_address_id).lock_current!(chain, actor:)
    ip.reload_current_assignment! unless actor
    chain.lock(self)
    reload(lock: true)
    if ip_address_id != ip.id
      raise ResourceLocked.new(self, 'Host address parent changed; retry the operation')
    end

    self.ip_address = ip
    self
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
