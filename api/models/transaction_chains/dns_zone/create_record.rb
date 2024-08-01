module TransactionChains
  class DnsZone::CreateRecord < ::TransactionChain
    label 'Record+'
    allow_empty

    # @param dns_record [::DnsRecord]
    # @return [::DnsRecord]
    def link_chain(dns_record)
      dns_zone = dns_record.dns_zone

      concerns(
        :affect,
        [dns_zone.class.name, dns_zone.id]
      )

      log = ::DnsRecordLog.create!(
        dns_zone:,
        change_type: 'create_record',
        name: dns_record.name,
        record_type: dns_record.record_type,
        content: dns_record.content
      )

      dns_zone.increment!(:serial)

      dns_zone.dns_server_zones.primary_type.each do |dns_server_zone|
        append_t(Transactions::DnsServerZone::CreateRecords, args: [dns_server_zone, [dns_record]])

        next unless dns_server_zone.dns_zone.enabled

        append_t(
          Transactions::DnsServer::Reload,
          args: [dns_server_zone.dns_server],
          kwargs: { zone: dns_zone.name }
        )
      end

      if empty?
        dns_record.confirmed = ::DnsRecord.confirmed(:confirmed)
        dns_record.save!
      else
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.create(dns_record)
          t.just_create(dns_record.update_token) if dns_record.update_token
          t.just_create(log)
        end
      end

      dns_record
    end
  end
end
