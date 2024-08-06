module TransactionChains
  class DnsZoneTransfer::Create < ::TransactionChain
    label 'Zone transfer+'
    allow_empty

    # @param zone_transfer [::DnsZoneTransfer]
    # @return [::DnsZoneTransfer]
    def link_chain(zone_transfer)
      concerns(
        :affect,
        [zone_transfer.dns_zone.class.name, zone_transfer.dns_zone_id]
      )

      dns_zone = zone_transfer.dns_zone
      lock(dns_zone)

      zone_transfer.save!

      dns_zone.dns_server_zones.each do |dns_server_zone|
        if dns_zone.internal_source? && dns_server_zone.primary_type?
          nameservers = [zone_transfer.server_name].compact
        end

        if zone_transfer.primary_type? && dns_server_zone.secondary_type?
          primaries = [zone_transfer.server_opts]
        end

        if zone_transfer.secondary_type?
          secondaries = [zone_transfer.server_opts]
        end

        append_t(
          Transactions::DnsServerZone::AddServers,
          args: [dns_server_zone],
          kwargs: {
            nameservers:,
            primaries:,
            secondaries:
          }.compact
        )

        append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      end

      if empty?
        zone_transfer.update!(confirmed: ::ZoneTransfer.confirmed(:confirmed))
        return zone_transfer
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.create(zone_transfer)
      end

      zone_transfer
    end
  end
end
