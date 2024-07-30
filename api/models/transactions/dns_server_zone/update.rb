module Transactions::DnsServerZone
  class Update < ::Transaction
    t_name :dns_zone_update
    t_type 5503
    queue :dns

    def params(dns_server_zone, new:, original:)
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        type: dns_server_zone.zone_type,
        new:,
        original:
      }
    end
  end
end
