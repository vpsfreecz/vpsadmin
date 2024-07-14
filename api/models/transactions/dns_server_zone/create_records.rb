module Transactions::DnsServerZone
  class CreateRecords < ::Transaction
    t_name :dns_zone_create_records
    t_type 5504
    queue :dns

    def params(dns_server_zone, dns_records)
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        serial: dns_server_zone.dns_zone.serial,
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
