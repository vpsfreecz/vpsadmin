module Transactions::DnsServerZone
  class UpdateRecords < ::Transaction
    t_name :dns_zone_update_records
    t_type 5505
    queue :dns

    def params(dns_server_zone, dns_records)
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        serial: dns_server_zone.dns_zone.serial,
        records: dns_records.map do |r|
          {
            new: {
              id: r.id,
              name: r.name,
              type: r.record_type,
              content: r.content,
              ttl: r.ttl,
              priority: r.priority
            },
            original: {
              id: r.id,
              name: r.name,
              type: r.record_type,
              content: r.content_was,
              ttl: r.ttl_was,
              priority: r.priority_was
            }
          }
        end
      }
    end
  end
end
