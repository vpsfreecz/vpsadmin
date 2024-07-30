module Transactions::DnsServerZone
  class RemoveServers < ::Transaction
    t_name :dns_zone_remove_servers
    t_type 5508
    queue :dns

    def params(dns_server_zone, nameservers: [], primaries: [], secondaries: [])
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        type: dns_server_zone.zone_type,
        nameservers:,
        primaries:,
        secondaries:
      }
    end
  end
end
