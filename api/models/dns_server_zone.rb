require_relative 'confirmable'

class DnsServerZone < ApplicationRecord
  belongs_to :dns_server
  belongs_to :dns_zone

  enum zone_type: %i[primary_type secondary_type]

  validate :check_zone_type

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
        # All secondary server zones are also added to primaries, so that it is enough
        # to notify only one secondary server, which will then send notification to other
        # secondary servers.
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
    # rubocop:disable Style/GuardClause
    if dns_zone.external_source? && primary_type?
      errors.add(:zone_type, "zone #{dns_zone.name} is external and must be of secondary type")
    end
    # rubocop:enable Style/GuardClause
  end
end
