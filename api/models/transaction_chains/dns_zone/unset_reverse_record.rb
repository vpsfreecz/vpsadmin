module TransactionChains
  class DnsZone::UnsetReverseRecord < ::TransactionChain
    label 'Unset PTR'
    allow_empty

    # @param host_ip_address [::HostIpAddress]
    # @return [::HostIpAddress]
    def link_chain(host_ip_address)
      lock(host_ip_address)

      dns_zone = host_ip_address.ip_address.reverse_dns_zone

      concerns(
        :affect,
        [host_ip_address.class.name, host_ip_address.id],
        [dns_zone.class.name, dns_zone.id]
      )

      record = host_ip_address.reverse_dns_record
      return if record.nil?

      host_ip_address.reverse_dns_record = nil

      log = ::DnsRecordLog.create!(
        user: ::User.current,
        dns_zone:,
        name: record.name,
        change_type: 'delete_record',
        record_type: 'PTR',
        attr_changes: { content: record.content }
      )

      dns_zone.increment!(:serial)

      dns_zone.dns_server_zones.primary_type.each do |dns_server_zone|
        append_t(Transactions::DnsServerZone::DeleteRecords, args: [dns_server_zone, [record]])

        next unless dns_server_zone.dns_zone.enabled

        append_t(
          Transactions::DnsServer::Reload,
          args: [dns_server_zone.dns_server],
          kwargs: { zone: dns_zone.name }
        )
      end

      if empty?
        record.destroy!
      else
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.just_create(log)

          record.update!(confirmed: ::DnsRecord.confirmed(:confirm_destroy))
          t.destroy(record)

          t.edit_before(host_ip_address, reverse_dns_record_id: host_ip_address.reverse_dns_record_id_was)
        end
      end

      host_ip_address.save!
      host_ip_address
    end
  end
end
