require_relative 'confirmable'
require_relative 'dns_zone_record_set_validator'

class DnsServerZone < ApplicationRecord
  belongs_to :dns_server
  belongs_to :dns_zone
  belongs_to :last_transfer_log,
             class_name: 'DnsServerZoneTransferLog',
             optional: true
  has_many :dns_server_zone_transfer_logs, dependent: :delete_all

  enum :zone_type, %i[primary_type secondary_type]
  enum :last_transfer_status, %i[started success failed], prefix: :last_transfer

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
      ip_addr:,
      tsig_key: nil
    }
  end

  # @return [Array<Hash>]
  def primaries
    ret = dns_zone.dns_zone_transfers.primary_type.map(&:server_opts)

    other_dns_server_zones =
      if dns_zone.internal_source?
        dns_zone.dns_server_zones.primary_type
      else
        # For external zones, peer vpsAdmin secondaries are added to primaries as
        # potential transfer sources. libnodectld then renders those peer
        # secondaries from #secondaries into BIND also-notify targets.
        dns_zone.dns_server_zones.all
      end

    ret.concat(other_dns_server_zones.where.not(id:).map(&:server_opts))

    ret
  end

  # @return [Array<Hash>]
  def secondaries
    ret = dns_zone.dns_zone_transfers.secondary_type.map(&:server_opts)
    ret.concat(dns_zone.dns_server_zones.secondary_type.where.not(id:).map(&:server_opts))
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
