module Transactions::DnsServerZone
  class CreateRecord < ::Transaction
    t_name :dns_zone_create_record
    t_type 5504
    queue :dns

    def params(dns_server_zone, dns_record)
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        serial: dns_server_zone.dns_zone.serial,
        record: {
          id: dns_record.id,
          name: dns_record.name,
          type: dns_record.record_type,
          content: dns_record.content,
          ttl: dns_record.ttl,
          priority: dns_record.priority
        }
      }
    end
  end
end
