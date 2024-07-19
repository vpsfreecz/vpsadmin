require 'base64'
require 'ipaddress'
require_relative 'confirmable'
require_relative 'lockable'

class DnsZone < ApplicationRecord
  belongs_to :user
  has_many :dns_server_zones
  has_many :dns_servers, through: :dns_server_zones
  has_many :dns_zone_transfers, dependent: :delete_all
  has_many :dns_records, dependent: :delete_all
  has_many :dns_record_logs, dependent: :delete_all
  has_many :ip_addresses, foreign_key: :reverse_dns_zone_id, dependent: :nullify

  enum zone_role: %i[forward_role reverse_role]
  enum zone_source: %i[internal_source external_source]

  validates :name, format: {
    with: /\A((?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)+[A-Za-z]{2,6}\.\Z/,
    message: '%{value} is not a valid zone name'
  }

  validate :check_name
  validate :check_source

  include Confirmable
  include Lockable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

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

    net_addr do |net|
      self_v = net.ipv4? ? 4 : 6

      check_addr = IPAddress.parse(addr)
      check_v = check_addr.ipv4? ? 4 : 6

      next(false) if self_v != check_v

      net.include?(check_addr)
    end
  end

  # rubocop:disable Style/GuardClause

  def check_name
    unless name.end_with?('.')
      errors.add(:name, 'not a canonical name (add trailing dot)')
    end
  end

  def check_source
    if internal_source? && user_id
      errors.add(:zone_source, 'user-owned zones must be external')
    end
  end

  # rubocop:enable Style/GuardClause

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
