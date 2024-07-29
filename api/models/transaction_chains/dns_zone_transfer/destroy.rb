module TransactionChains
  class DnsZoneTransfer::Destroy < ::TransactionChain
    label 'Zone transfer-'
    allow_empty

    # @param zone_transfer [::DnsZoneTransfer]
    def link_chain(zone_transfer)
      concerns(
        :affect,
        [zone_transfer.dns_zone.class.name, zone_transfer.dns_zone_id]
      )

      dns_zone = zone_transfer.dns_zone
      lock(dns_zone)

      update_kwargs =
        if dns_zone.internal_source?
          {
            nameservers: [zone_transfer.server_name].compact,
            secondaries: [zone_transfer.server_opts]
          }
        else
          {
            primaries: [zone_transfer.server_opts]
          }
        end

      dns_zone.dns_server_zones.each do |dns_server_zone|
        append_t(
          Transactions::DnsServerZone::RemoveServers,
          args: [dns_server_zone],
          kwargs: update_kwargs
        )

        append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      end

      if empty?
        zone_transfer.destroy!
        return
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        zone_transfer.update!(confirmed: ::DnsZoneTransfer.confirmed(:confirm_destroy))
        t.destroy(zone_transfer)
      end

      nil
    end
  end
end
