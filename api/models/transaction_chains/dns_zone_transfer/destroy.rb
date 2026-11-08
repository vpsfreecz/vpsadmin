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

      zone_transfer.host_ip_address.lock_with_ip!(self)
      dns_zone = zone_transfer.dns_zone
      lock(dns_zone)
      server_zones = dns_zone.dns_server_zones.order(:id).lock.to_a
      zone_transfer.reload(lock: true)
      dns_zone.rotate_primary_transfer_generation! if zone_transfer.primary_type?

      server_zones.each do |dns_server_zone|
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
          Transactions::DnsServerZone::RemoveServers,
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
        zone_transfer.destroy!
        return
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        server_zones.each do |dns_server_zone|
          dns_server_zone.dns_server_zone_primary_transfer_states
                         .where(dns_zone_transfer: zone_transfer)
                         .each { |state| t.just_destroy(state) }
        end

        zone_transfer.update!(confirmed: ::DnsZoneTransfer.confirmed(:confirm_destroy))
        t.destroy(zone_transfer)
      end

      nil
    end
  end
end
