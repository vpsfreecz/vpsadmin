module Transactions::DnsServerZone
  class Create < ::Transaction
    t_name :dns_zone_create
    t_type 5501
    queue :dns

    def params(dns_server_zone)
      self.node_id = dns_server_zone.dns_server.node_id

      ret = {
        name: dns_server_zone.dns_zone.name,
        source: dns_server_zone.dns_zone.zone_source,
        enabled: dns_server_zone.dns_zone.enabled,
        tsig_algorithm: dns_server_zone.dns_zone.tsig_algorithm,
        tsig_key: dns_server_zone.dns_zone.tsig_key
      }

      if dns_server_zone.dns_zone.internal_source?
        ret.update(
          default_ttl: dns_server_zone.dns_zone.default_ttl,
          serial: dns_server_zone.dns_zone.serial,
          email: dns_server_zone.dns_zone.email,
          nameservers: dns_server_zone.dns_zone.nameservers,
          primaries: [],
          secondaries: dns_server_zone.dns_zone.dns_zone_transfers.secondary_type.map(&:ip_addr),
          records: dns_server_zone.dns_zone.dns_records.where(enabled: true).map do |r|
            {
              id: r.id,
              name: r.name,
              type: r.record_type,
              content: r.content,
              ttl: r.ttl
            }
          end
        )
      else
        ret.update(
          primaries: dns_server_zone.dns_zone.dns_zone_transfers.primary_type.map(&:ip_addr),
          secondaries: []
        )
      end

      ret
    end
  end
end
