class HostIpAddress < ApplicationRecord
  belongs_to :ip_address
  has_many :routed_via_addresses,
           class_name: 'IpAddress', foreign_key: :route_via_id
  belongs_to :reverse_dns_record, class_name: 'DnsRecord'

  include Lockable

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
    ip = ip_address.to_ip

    case ip_address.network.ip_version
    when 4
      "#{ip.octets.reverse.join('.')}.in-addr.arpa."
    when 6
      "#{ip.address.split(':').map(&:chars).flatten.reverse.join('.')}.ip6.arpa."
    end
  end
end
