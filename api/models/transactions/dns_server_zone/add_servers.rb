module Transactions::DnsServerZone
  class AddServers < ::Transaction
    t_name :dns_zone_add_servers
    t_type 5507
    queue :dns

    def params(dns_server_zone, nameservers: [], primaries: [], secondaries: [])
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        nameservers:,
        primaries:,
        secondaries:
      }
    end
  end
end
