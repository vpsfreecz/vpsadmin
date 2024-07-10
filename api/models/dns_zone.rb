require 'base64'
require 'ipaddress'

class DnsZone < ApplicationRecord
  has_many :dns_server_zones
  has_many :dns_servers, through: :dns_server_zones
  has_many :dns_zone_transfers, dependent: :delete_all
  has_many :dns_records, dependent: :delete_all
  has_many :dns_record_logs, dependent: :delete_all
  has_many :ip_addresses, foreign_key: :reverse_dns_zone_id, dependent: :nullify

  enum zone_role: %i[forward_role reverse_role]
  enum zone_source: %i[internal_source external_source]

  validates :tsig_algorithm, inclusion: {
    in: %w[none hmac-sha224 hmac-sha256 hmac-sha384 hmac-sha512],
    message: '%{value} is not a valid TSIG algorithm'
  }

  validate :check_name
  validate :check_tsig_key

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

  def check_tsig_key
    return if tsig_key.empty?

    begin
      return if Base64.strict_encode64(Base64.strict_decode64(tsig_key)) == tsig_key
    rescue ArgumentError
      # pass
    end

    errors.add(:tsig_key, 'not a valid base64 string')
  end

  # @return [Array<String>]
  def nameservers
    raise '#nameservers can only be called on internal zones' unless internal_source?

    ret = dns_server_zones.reload.map(&:server_name)
    ret.concat(dns_zone_transfers.map(&:server_name))
    ret.compact
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
