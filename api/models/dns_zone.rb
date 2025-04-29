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
  has_many :dns_record_logs, dependent: :nullify
  has_many :dnssec_records, dependent: :delete_all
  has_many :ip_addresses, foreign_key: :reverse_dns_zone_id, dependent: :nullify

  enum :zone_role, %i[forward_role reverse_role]
  enum :zone_source, %i[internal_source external_source]

  validates :name, format: {
    with: /\A((?!-)[A-Za-z0-9\-_]{1,63}(?<!-)\.)+[A-Za-z]{2,63}\.\z/,
    message: '%{value} is not a valid zone name'
  }

  validates :default_ttl, presence: true, numericality: { in: (60..(7 * 86_400)) }

  validates :email, presence: true, format: {
    with: /\A[^@\s]+@[^\s]+\z/,
    message: '%{value} is not a valid email address'
  }, if: :internal_source?

  validate :check_name

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

  def check_name
    unless name.end_with?('.')
      errors.add(:name, 'not a canonical name (add trailing dot)')
    end

    return if ::User.current.nil? || ::User.current.role == :admin

    (SysConfig.get(:dns, :protected_zones) || []).each do |prot_name|
      if name == prot_name || name.end_with?(".#{prot_name}")
        errors.add(:name, "zone #{prot_name} is protected and cannot be used")
      end
    end
  end

  # @return [Array<String>]
  def nameservers
    raise '#nameservers can only be called on internal zones' unless internal_source?

    ret = dns_server_zones.reload.reject { |dsz| dsz.dns_server.hidden }.map(&:server_name)
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
