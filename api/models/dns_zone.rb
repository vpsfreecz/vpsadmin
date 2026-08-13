require 'base64'
require 'ipaddress'
require 'securerandom'
require_relative 'confirmable'
require_relative 'lockable'

class DnsZone < ApplicationRecord
  belongs_to :user
  has_many :dns_server_zones
  has_many :dns_server_zone_primary_transfer_states, through: :dns_server_zones
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
  validates :name, presence: true

  validates :default_ttl, presence: true, numericality: { in: (60..(7 * 86_400)) }

  validates :email, presence: true, format: {
    with: /\A[^@\s]+@[^\s]+\z/,
    message: '%{value} is not a valid email address'
  }, if: :internal_source?

  validate :check_name

  before_validation :set_primary_transfer_tracking_started_at,
                    if: -> { new_record? || will_save_change_to_enabled? || will_save_change_to_zone_source? }
  after_update :reset_primary_transfer_states,
               if: -> { saved_change_to_enabled? || saved_change_to_zone_source? }

  include Confirmable
  include Lockable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

  scope :with_alert_eligible_primary_transfer_state_counts, lambda { |at: Time.current|
    states = ::DnsServerZonePrimaryTransferState
             .joins(:dns_zone_transfer, dns_server_zone: :dns_server)
             .merge(::DnsServerZone.existing.secondary_type)
             .merge(::DnsZoneTransfer.existing.primary_type)
             .where(dns_servers: { hidden: false })
             .where('dns_server_zones.dns_zone_id = dns_zones.id')
             .where('dns_zone_transfers.dns_zone_id = dns_zones.id')
    alert_eligible_states = states.alert_eligible_at(at).select('COUNT(*)')
    failed_states = states.failed.select('COUNT(*)')

    select(
      'dns_zones.*',
      "(#{alert_eligible_states.to_sql}) AS alert_eligible_primary_transfer_state_count",
      "(#{failed_states.to_sql}) AS failed_primary_transfer_state_count"
    )
  }

  def include?(what)
    if zone_role != 'reverse_role'
      raise '#include? can be called only on reverse zones'
    end

    return false if reverse_network_address.blank? || reverse_network_prefix.blank?

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

  # Increment serial and return the new value
  # @return [Integer]
  def increment_serial
    increment!(:serial)
    self.class.find(id).serial
  end

  # @return [Array<String>]
  def nameservers
    raise '#nameservers can only be called on internal zones' unless internal_source?

    ret = dns_server_zones.reload.reject { |dsz| dsz.dns_server.hidden }.map(&:server_name)
    ret.concat(dns_zone_transfers.map(&:server_name))
    ret.compact
  end

  def alert_eligible_primary_transfer_states(at: Time.current)
    ::DnsServerZonePrimaryTransferState
      .includes(:dns_zone_transfer, dns_server_zone: :dns_server)
      .joins(:dns_zone_transfer, dns_server_zone: :dns_server)
      .merge(::DnsServerZone.existing.secondary_type)
      .merge(::DnsZoneTransfer.existing.primary_type)
      .where(dns_server_zones: { dns_zone_id: id })
      .where(dns_servers: { hidden: false })
      .where(dns_zone_transfers: { dns_zone_id: id })
      .alert_eligible_at(at)
  end

  def alert_eligible_primary_transfer_state_count(at: Time.current)
    selected = self[:alert_eligible_primary_transfer_state_count]
    return selected.to_i unless selected.nil?

    alert_eligible_primary_transfer_states(at:).count
  end

  def failed_primary_transfer_state_count
    selected = self[:failed_primary_transfer_state_count]
    return selected.to_i unless selected.nil?

    dns_server_zone_primary_transfer_states.failed.count
  end

  def primary_transfer_failure_monitor_passed?(incident_active:)
    return true unless enabled? && external_source?

    failure_count =
      if incident_active
        failed_primary_transfer_state_count
      else
        alert_eligible_primary_transfer_state_count
      end

    failure_count == 0
  end

  def rotate_primary_transfer_generation!
    return unless enabled? && external_source?

    update!(
      primary_transfer_tracking_started_at: Time.current,
      primary_transfer_generation: SecureRandom.uuid
    )
  end

  protected

  def set_primary_transfer_tracking_started_at
    if enabled? && external_source?
      self.primary_transfer_tracking_started_at = Time.current
      self.primary_transfer_generation = SecureRandom.uuid
    else
      self.primary_transfer_tracking_started_at = nil
      self.primary_transfer_generation = nil
    end
  end

  def reset_primary_transfer_states
    dns_server_zones.order(:id).each do |server_zone|
      server_zone.with_lock do
        server_zone.dns_server_zone_primary_transfer_states.delete_all
      end
    end
  end

  def net_addr(force = false)
    @net_addr = IPAddress.parse("#{reverse_network_address}/#{reverse_network_prefix}") if force || @net_addr.nil?

    if block_given?
      yield(@net_addr)

    else
      @net_addr
    end
  end
end
