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

      base_nameservers = dns_zone.nameservers if dns_zone.internal_source?
      base_primaries = dns_zone.dns_zone_transfers.primary_type.map(&:server_opts)
      base_secondaries = dns_zone.dns_zone_transfers.secondary_type.map(&:server_opts)

      update_kwargs =
        if dns_zone.internal_source?
          {
            new: {
              nameservers: base_nameservers + [zone_transfer.server_name].compact,
              secondaries: base_secondaries + zone_transfer.server_opts
            },
            original: {
              nameservers: base_nameservers,
              secondaries: base_secondaries
            }
          }
        else
          {
            new: {
              primaries: base_primaries + [zone_transfer.server_opts]
            },
            original: {
              primaries: base_primaries
            }
          }
        end

      zone_transfer.save!

      dns_zone.dns_server_zones.each do |dns_server_zone|
        append_t(
          Transactions::DnsServerZone::Update,
          args: [dns_server_zone],
          kwargs: update_kwargs
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
