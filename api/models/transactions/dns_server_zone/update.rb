module Transactions::DnsServerZone
  class Update < ::Transaction
    t_name :dns_zone_update
    t_type 5503
    queue :dns

    def params(dns_server_zone, new:, original:)
      self.node_id = dns_server_zone.dns_server.node_id

      {
        id: dns_server_zone.id,
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        type: dns_server_zone.zone_type,
        primary_transfer_generation: dns_server_zone.primary_transfer_configuration_generation,
        primary_transfer_tracking_started_at:
          dns_server_zone.dns_zone.primary_transfer_tracking_started_at&.to_i,
        probe_source_addrs: dns_server_zone.probe_source_addrs,
        new:,
        original:
      }
    end
  end
end
