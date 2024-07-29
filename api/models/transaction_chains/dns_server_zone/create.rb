module TransactionChains
  class DnsServerZone::Create < ::TransactionChain
    label 'Server zone+'

    # @param dns_server_zone [::DnsServerZone]
    # @return [::DnsServerZone]
    def link_chain(dns_server_zone)
      concerns(
        :affect,
        [dns_server_zone.dns_server.class.name, dns_server_zone.dns_server_id],
        [dns_server_zone.dns_zone.class.name, dns_server_zone.dns_zone_id]
      )

      # Create the new server zone
      dns_server_zone.save!

      append_t(Transactions::DnsServerZone::Create, args: [dns_server_zone]) do |t|
        t.create(dns_server_zone)
      end

      append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])

      if dns_server_zone.dns_zone.internal_source?
        dns_server_zone.dns_zone.dns_server_zones.each do |other_dns_server_zone|
          next if other_dns_server_zone == dns_server_zone

          append_t(
            Transactions::DnsServerZone::AddServers,
            args: [other_dns_server_zone],
            kwargs: {
              nameservers: [dns_server_zone.dns_server.name]
            }
          )

          append_t(
            Transactions::DnsServer::Reload,
            args: [other_dns_server_zone.dns_server],
            kwargs: { zone: dns_server_zone.dns_zone.name }
          )
        end
      end

      dns_server_zone
    end
  end
end
