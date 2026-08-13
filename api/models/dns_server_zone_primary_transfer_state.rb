class DnsServerZonePrimaryTransferState < ApplicationRecord
  PRIMARY_ALERT_DELAY = 30.minutes
  NETWORK_ALERT_DELAY = 24.hours
  FAILURE_CONTINUITY_GAP = 15.minutes
  SLOW_FAILURE_CONTINUITY_GAP = 75.minutes
  SLOW_PROBE_REASON_CODES = %w[invalid_zone protocol_error stale].freeze

  belongs_to :dns_server_zone
  belongs_to :dns_zone_transfer
  belongs_to :last_transfer_log,
             class_name: 'DnsServerZoneTransferLog',
             optional: true

  enum :status, %i[unknown success failed]
  enum :failure_class, %i[primary network]
  enum :last_attempt_kind,
       %i[transfer refresh notify load ixfr_probe axfr_probe],
       prefix: :last_attempt

  validates :dns_server_zone, :dns_zone_transfer, :status, :last_attempt_at,
            :last_attempt_kind, :last_event_key, :configuration_generation,
            presence: true
  validates :dns_zone_transfer_id, uniqueness: { scope: :dns_server_zone_id }
  validates :failed_since, :last_failure_at, :failure_class,
            presence: true, if: :failed?
  validate :check_same_zone

  scope :alert_eligible_at, lambda { |at|
    failed.where.not(alert_eligible_at: nil).where('alert_eligible_at <= ?', at)
  }

  def alert_delay
    network? ? NETWORK_ALERT_DELAY : PRIMARY_ALERT_DELAY
  end

  def secondary_source_addr
    server = dns_server_zone.dns_server
    dns_zone_transfer.ip_addr.include?(':') ? server.ipv6_addr : server.ipv4_addr
  end

  protected

  def check_same_zone
    return unless dns_server_zone && dns_zone_transfer
    return if dns_server_zone.dns_zone_id == dns_zone_transfer.dns_zone_id

    errors.add(:dns_zone_transfer, 'must belong to the same DNS zone')
  end
end
