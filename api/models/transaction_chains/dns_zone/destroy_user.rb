module TransactionChains
  class DnsZone::DestroyUser < ::TransactionChain
    label 'Destroy zone'
    allow_empty

    # @param dns_zone [::DnsZone]
    def link_chain(dns_zone)
      concerns(:affect, [dns_zone.class.name, dns_zone.id])

      dns_zone.dns_server_zones.each do |dns_server_zone|
        append_t(Transactions::DnsServerZone::Destroy, args: [dns_server_zone]) do |t|
          t.just_destroy(dns_server_zone)
        end

        append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      end

      if empty?
        dns_zone.destroy!
        return
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        dns_zone.dns_zone_transfers.each do |zone_transfer|
          t.just_destroy(zone_transfer)
        end

        t.just_destroy(dns_zone)
      end

      nil
    end
  end
end
