module TransactionChains
  class DnsServerZone::Destroy < ::TransactionChain
    label 'Server zone-'

    # @param dns_server_zone [::DnsServerZone]
    def link_chain(dns_server_zone)
      concerns(
        :affect,
        [dns_server_zone.dns_server.class.name, dns_server_zone.dns_server_id],
        [dns_server_zone.dns_zone.class.name, dns_server_zone.dns_zone_id]
      )

      nameservers = dns_server_zone.dns_zone.nameservers if dns_server_zone.dns_zone.internal_source?

      append_t(Transactions::DnsServerZone::Destroy, args: [dns_server_zone]) do |t|
        dns_server_zone.update!(confirmed: ::DnsServerZone.confirmed(:confirm_destroy))
        t.destroy(dns_server_zone)
      end

      append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])

      return if dns_server_zone.dns_zone.external_source?

      dns_server_zone.dns_zone.dns_server_zones.each do |other_dns_server_zone|
        next if other_dns_server_zone == dns_server_zone

        append_t(
          Transactions::DnsServerZone::Update,
          args: [other_dns_server_zone],
          kwargs: {
            new: {
              nameservers: nameservers - [dns_server_zone.dns_server.name]
            },
            original: {
              nameservers:
            }
          }
        )

        append_t(
          Transactions::DnsServer::Reload,
          args: [other_dns_server_zone.dns_server],
          kwargs: { zone: dns_server_zone.dns_zone.name }
        )
      end

      nil
    end
  end
end
