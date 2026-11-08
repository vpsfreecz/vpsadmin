module Transactions::DnsServerZone
  class RemoveServers < ::Transaction
    t_name :dns_zone_remove_servers
    t_type 5508
    queue :dns

    def params(dns_server_zone, nameservers: [], primaries: [], secondaries: [])
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
        nameservers:,
        primaries:,
        secondaries:
      }
    end
  end
end
