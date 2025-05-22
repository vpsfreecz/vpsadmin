module Transactions::DnsServerZone
  class DeleteRecords < ::Transaction
    t_name :dns_zone_delete_records
    t_type 5506
    queue :dns

    def params(dns_server_zone:, dns_records:, serial:)
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        type: dns_server_zone.zone_type,
        serial:,
        records: dns_records.map do |r|
          {
            id: r.id,
            name: r.name,
            type: r.record_type,
            content: r.content,
            ttl: r.ttl,
            priority: r.priority
          }
        end
      }
    end
  end
end
