module TransactionChains
  class DnsZone::Destroy < ::TransactionChain
    label 'Destroy zone'

    # @param dns_server_zone [::DnsServerZone]
    def link_chain(dns_server_zone)
      concerns(
        :affect,
        [dns_server_zone.dns_server.class.name, dns_server_zone.dns_server_id],
        [dns_server_zone.dns_zone.class.name, dns_server_zone.dns_zone_id]
      )

      nameservers = dns_server_zone.dns_zone.dns_servers.pluck(:name)

      append_t(Transactions::DnsZone::Destroy, args: [dns_server_zone]) do |t|
        t.just_destroy(dns_server_zone)
      end

      append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])

      # Update the zone on all other servers for NS records
      dns_server_zone.dns_zone.dns_server_zones.each do |other_dns_server_zone|
        next if other_dns_server_zone == dns_server_zone

        append_t(
          Transactions::DnsZone::Update,
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

        append_t(Transactions::DnsServer::Reload, args: [other_dns_server_zone.dns_server])
      end

      nil
    end
  end
end
