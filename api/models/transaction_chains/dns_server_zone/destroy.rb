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

      append_t(Transactions::DnsServerZone::Destroy, args: [dns_server_zone]) do |t|
        dns_server_zone.update!(confirmed: ::DnsServerZone.confirmed(:confirm_destroy))
        t.destroy(dns_server_zone)
      end

      append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])

      dns_server_zone.dns_zone.dns_server_zones.each do |other_dns_server_zone|
        next if other_dns_server_zone == dns_server_zone

        if dns_server_zone.dns_zone.internal_source?
          nameservers = dns_server_zone.dns_server.hidden ? [] : [dns_server_zone.dns_server.name]

          if dns_server_zone.primary_type? && other_dns_server_zone.secondary_type?
            primaries = [dns_server_zone.server_opts]
          end

          if dns_server_zone.secondary_type? && other_dns_server_zone.primary_type?
            secondaries = [dns_server_zone.server_opts]
          end
        else
          primaries = [dns_server_zone.server_opts]
          secondaries = [dns_server_zone.server_opts]
        end

        next if nameservers.nil? && primaries.nil? && secondaries.nil?

        append_t(
          Transactions::DnsServerZone::RemoveServers,
          args: [other_dns_server_zone],
          kwargs: {
            nameservers:,
            primaries:,
            secondaries:
          }.compact
        )

        append_t(Transactions::DnsServer::Reload, args: [other_dns_server_zone.dns_server])
      end

      nil
    end
  end
end
