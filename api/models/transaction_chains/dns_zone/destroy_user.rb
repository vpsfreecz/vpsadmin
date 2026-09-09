module TransactionChains
  class DnsZone::DestroyUser < ::TransactionChain
    label 'Zone-'
    allow_empty

    # @param dns_zone [::DnsZone]
    def link_chain(dns_zone)
      hosts = ::HostIpAddress.where(id: dns_zone.dns_zone_transfers.select(:host_ip_address_id))
                             .order(:ip_address_id, :id).to_a
      hosts.each { |host| host.lock_with_ip!(self) }
      lock(dns_zone)
      transfers = dns_zone.dns_zone_transfers.order(:id).lock.to_a
      unless (transfers.map(&:host_ip_address_id) - hosts.map(&:id)).empty?
        raise ResourceLocked.new(dns_zone, 'DNS zone transfers changed; retry zone removal')
      end

      concerns(:affect, [dns_zone.class.name, dns_zone.id])

      dns_zone.dns_server_zones.each do |dns_server_zone|
        append_t(Transactions::DnsServerZone::Destroy, args: [dns_server_zone]) do |t|
          dns_server_zone.update!(confirmed: ::DnsServerZone.confirmed(:confirm_destroy))
          t.destroy(dns_server_zone)
        end

        append_t(Transactions::DnsServer::Reload, args: [dns_server_zone.dns_server])
      end

      if empty?
        dns_zone.destroy!
        return
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        transfers.each do |zone_transfer|
          zone_transfer.update!(confirmed: ::DnsZoneTransfer.confirmed(:confirm_destroy))
          t.destroy(zone_transfer)
        end

        dns_zone.dns_records.each do |r|
          t.just_destroy(r.update_token) if r.update_token

          r.update!(confirmed: ::DnsRecord.confirmed(:confirm_destroy))
          t.destroy(r)
        end

        dns_zone.dns_record_logs.each do |log|
          t.edit(log, dns_zone_id: nil)
        end

        dns_zone.dnssec_records.each do |r|
          t.just_destroy(r)
        end

        dns_zone.update!(confirmed: ::DnsZone.confirmed(:confirm_destroy))
        t.destroy(dns_zone)
      end

      nil
    end
  end
end
