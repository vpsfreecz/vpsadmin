require_relative 'confirmable'
require_relative 'dns_zone_record_set_validator'

class DnsServerZone < ApplicationRecord
  STATUS_STALE_AFTER = 5.minutes
  belongs_to :dns_server
  belongs_to :dns_zone
  belongs_to :last_transfer_log,
             class_name: 'DnsServerZoneTransferLog',
             optional: true
  has_many :dns_server_zone_transfer_logs, dependent: :delete_all
  has_many :dns_server_zone_primary_transfer_states, dependent: :delete_all

  enum :zone_type, %i[primary_type secondary_type]
  enum :last_transfer_status, %i[success failed], prefix: :last_transfer

  validates :dns_server, presence: true
  validates :dns_zone, presence: true

  validate :check_zone_type
  validate :check_zone_record_set

  include Confirmable

  scope :existing, lambda {
    where(confirmed: [confirmed(:confirm_create), confirmed(:confirmed)])
  }

  # @return [String]
  def ip_addr
    dns_server.node.ip_addr
  end

  # @return [String]
  def server_name
    dns_server.name
  end

  def server_opts
    {
      id:,
      kind: 'vpsadmin_peer',
      ip_addr:,
      tsig_key: nil
    }
  end

  def probe_source_addrs
    {
      ipv4: dns_server.ipv4_addr,
      ipv6: dns_server.ipv6_addr
    }
  end

  def primary_transfer_configuration_generation
    dns_zone.primary_transfer_generation
  end

  # Call only after reserving every involved zone. Locking reads deliberately
  # materialize current rows even in the test database's REPEATABLE-READ view.
  def self.lock_configuration(zones, servers: [])
    zones = ::DnsZone.where(id: zones.map(&:id)).order(:id).lock.to_a
    server_zones = existing.where(dns_zone: zones).order(:id).lock.to_a
    servers = ::DnsServer.where(id: server_zones.map(&:dns_server_id) + servers.map(&:id)).order(:id).lock.to_a
    transfers = ::DnsZoneTransfer.existing.where(dns_zone: zones).order(:id).lock.to_a
    zones_by_id = zones.index_by(&:id)
    servers_by_id = servers.index_by(&:id)
    server_zones.each do |server_zone|
      server_zone.dns_zone = zones_by_id.fetch(server_zone.dns_zone_id)
      server_zone.dns_server = servers_by_id.fetch(server_zone.dns_server_id)
    end
    { zones:, server_zones:, servers:, transfers: }
  end

  def configuration_attrs(server_zones: nil, transfers: nil, **)
    server_zones = server_zones&.select { |entry| entry.dns_zone_id == dns_zone_id }
    transfers = transfers&.select { |entry| entry.dns_zone_id == dns_zone_id }
    {
      enabled: dns_zone.enabled,
      primaries: primaries(server_zones:, transfers:),
      secondaries: secondaries(server_zones:, transfers:),
      probe_source_addrs:,
      primary_transfer_generation: primary_transfer_configuration_generation,
      primary_transfer_tracking_started_at: dns_zone.primary_transfer_tracking_started_at&.to_i
    }
  end

  def zone_status(at: Time.current)
    return 'unknown' if last_check_at.nil? || last_check_at < at - STATUS_STALE_AFTER
    return 'not_loaded' if serial.nil? || loaded_at.nil?
    return 'expired' if expires_at && expires_at <= at

    'serving'
  end

  # @return [Array<Hash>]
  def primaries(server_zones: nil, transfers: nil)
    transfers ||= dns_zone.dns_zone_transfers.existing.to_a
    server_zones ||= dns_zone.dns_server_zones.existing.to_a
    ret = transfers.select(&:primary_type?).map(&:server_opts)

    other_dns_server_zones =
      if dns_zone.internal_source?
        server_zones.select(&:primary_type?)
      else
        # For external zones, peer vpsAdmin secondaries are added to primaries as
        # potential transfer sources. libnodectld then renders those peer
        # secondaries from #secondaries into BIND also-notify targets.
        server_zones
      end

    ret.concat(other_dns_server_zones.reject { |entry| entry.id == id }.map(&:server_opts))

    ret
  end

  # @return [Array<Hash>]
  def secondaries(server_zones: nil, transfers: nil)
    transfers ||= dns_zone.dns_zone_transfers.existing.to_a
    server_zones ||= dns_zone.dns_server_zones.existing.to_a
    ret = transfers.select(&:secondary_type?).map(&:server_opts)
    ret.concat(server_zones.select { |entry| entry.secondary_type? && entry.id != id }.map(&:server_opts))
    ret
  end

  protected

  def check_zone_type
    return unless dns_zone.external_source? && primary_type?

    message = "zone #{dns_zone.name} is external and must be of secondary type"
    errors.add(:zone_type, message)
    errors.add(:type, message)
  end

  def check_zone_record_set
    return unless dns_zone && dns_zone.internal_source? && primary_type?
    return unless new_record? || will_save_change_to_dns_zone_id? || will_save_change_to_zone_type?

    DnsZoneRecordSetValidator.validate_zone(dns_zone, errors:, attribute: :dns_zone)
  end
end
