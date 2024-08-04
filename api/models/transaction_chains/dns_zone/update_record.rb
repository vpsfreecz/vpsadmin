module TransactionChains
  class DnsZone::UpdateRecord < ::TransactionChain
    label 'Record*'
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
        change_type: 'update_record',
        name: dns_record.name,
        record_type: dns_record.record_type,
        attr_changes: dns_record.changes.to_h do |attr, values|
          _old_value, new_value = values
          [attr, new_value]
        end
      )

      dns_zone.increment!(:serial)

      dns_zone.dns_server_zones.primary_type.each do |dns_server_zone|
        if dns_record.enabled_changed?
          if dns_record.enabled
            append_t(Transactions::DnsServerZone::CreateRecords, args: [dns_server_zone, [dns_record]])
          else
            append_t(Transactions::DnsServerZone::DeleteRecords, args: [dns_server_zone, [dns_record]])
          end
        elsif dns_record.enabled
          append_t(Transactions::DnsServerZone::UpdateRecords, args: [dns_server_zone, [dns_record]])
        else
          next
        end

        next unless dns_server_zone.dns_zone.enabled

        append_t(
          Transactions::DnsServer::Reload,
          args: [dns_server_zone.dns_server],
          kwargs: { zone: dns_zone.name }
        )
      end

      unless empty?
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          db_changes = dns_record.changes.to_h do |attr, values|
            old_value, _new_value = values
            [attr, old_value]
          end

          t.edit_before(dns_record, **db_changes)
          t.just_create(log)
        end
      end

      dns_record.save!
      dns_record
    end
  end
end