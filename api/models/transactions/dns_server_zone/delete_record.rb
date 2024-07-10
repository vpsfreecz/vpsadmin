module Transactions::DnsServerZone
  class DeleteRecord < ::Transaction
    t_name :dns_zone_delete_record
    t_type 5506
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
          ttl: dns_record.ttl
        }
      }
    end
  end
end
