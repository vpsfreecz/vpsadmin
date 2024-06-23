require 'ipaddress'

class DnsZone < ApplicationRecord
  has_many :dns_server_zones
  has_many :dns_servers, through: :dns_server_zones
  has_many :dns_records
  has_many :dns_record_logs
  has_many :ip_addresses, foreign_key: :reverse_dns_zone_id, dependent: :nullify

  enum zone_type: %i[primary_type secondary_type]
  enum zone_role: %i[forward_role reverse_role]

  validate :check_name

  def include?(what)
    if zone_role != 'reverse_role'
      raise '#include? can be called only on reverse zones'
    end

    case what
    when ::IpAddress # model
      addr = what.addr

    when ::Network
      addr = "#{what.address}/#{what.prefix}"

    when ::String
      addr = what

    when ::IPAddress::IPv4, ::IPAddress::IPv6 # gem lib
      return net_addr { |n| n.include?(what) }
    end

    net_addr { |n| n.include?(IPAddress.parse(addr)) }
  end

  def check_name
    return if name.end_with?('.')

    errors.add(:name, 'not a canonical name (add trailing dot)')
  end

  protected

  def net_addr(force = false)
    @net_addr = IPAddress.parse("#{reverse_network_address}/#{reverse_network_prefix}") if force || @net_addr.nil?

    if block_given?
      yield(@net_addr)

    else
      @net_addr
    end
  end
end
