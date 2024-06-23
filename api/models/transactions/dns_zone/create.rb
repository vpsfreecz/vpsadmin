module Transactions::DnsZone
  class Create < ::Transaction
    t_name :dns_zone_create
    t_type 5501
    queue :dns

    def params(dns_server_zone)
      self.node_id = dns_server_zone.dns_server.node_id

      {
        name: dns_server_zone.dns_zone.name,
        default_ttl: dns_server_zone.dns_zone.default_ttl,
        nameservers: dns_server_zone.dns_zone.dns_servers.pluck(:name),
        serial: dns_server_zone.dns_zone.serial,
        email: dns_server_zone.dns_zone.email,
        records: dns_server_zone.dns_zone.dns_records.where(enabled: true).map do |r|
          {
            id: r.id,
            name: r.name,
            type: r.record_type,
            content: r.content,
            ttl: r.ttl
          }
        end
      }
    end
  end
end
