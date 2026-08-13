module TransactionChains
  class DnsServerZone::RefreshConfiguration < ::TransactionChain
    label 'Refresh DNS server zone configuration'

    def link_chain(dns_server_zone)
      concerns(
        :affect,
        [dns_server_zone.dns_zone.class.name, dns_server_zone.dns_zone_id],
        [dns_server_zone.dns_server.class.name, dns_server_zone.dns_server_id]
      )

      attrs = {
        enabled: dns_server_zone.dns_zone.enabled,
        primaries: dns_server_zone.primaries,
        secondaries: dns_server_zone.secondaries
      }

      append_t(
        Transactions::DnsServerZone::Update,
        args: [dns_server_zone],
        kwargs: { new: attrs, original: attrs }
      )
      append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      dns_server_zone
    end
  end
end
