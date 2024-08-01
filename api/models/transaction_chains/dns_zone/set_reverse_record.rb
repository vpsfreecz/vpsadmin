module TransactionChains
  class DnsZone::SetReverseRecord < ::TransactionChain
    label 'Set PTR'
    allow_empty

    # @param host_ip_address [::HostIpAddress]
    # @param ptr_content [String]
    # @return [::HostIpAddress]
    def link_chain(host_ip_address, ptr_content)
      lock(host_ip_address)

      dns_zone = host_ip_address.ip_address.reverse_dns_zone

      concerns(
        :affect,
        [host_ip_address.class.name, host_ip_address.id],
        [dns_zone.class.name, dns_zone.id]
      )

      record = host_ip_address.reverse_dns_record

      if record
        record.content = ptr_content
        created = false
      else
        if /\A(.+)\.#{Regexp.escape(dns_zone.name)}\z/ !~ host_ip_address.reverse_record_domain
          raise "Unable to find reverse record name for #{host_ip_address} in zone #{dns_zone.name}"
        end

        record_name = Regexp.last_match(1)

        record = ::DnsRecord.create!(
          dns_zone:,
          name: record_name,
          record_type: 'PTR',
          content: ptr_content,
          host_ip_address:
        )
        host_ip_address.reverse_dns_record = record
        created = true
      end

      log = ::DnsRecordLog.create!(
        dns_zone:,
        change_type: created ? 'create_record' : 'update_record',
        name: record.name,
        record_type: 'PTR',
        content: ptr_content
      )

      dns_zone.increment!(:serial)

      dns_zone.dns_server_zones.primary_type.each do |dns_server_zone|
        if created
          append_t(Transactions::DnsServerZone::CreateRecords, args: [dns_server_zone, [record]])
        else
          append_t(Transactions::DnsServerZone::UpdateRecords, args: [dns_server_zone, [record]])
        end

        next unless dns_server_zone.dns_zone.enabled

        append_t(
          Transactions::DnsServer::Reload,
          args: [dns_server_zone.dns_server],
          kwargs: { zone: dns_zone.name }
        )
      end

      if empty?
        record.confirmed = ::DnsRecord.confirmed(:confirmed)
      else
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          if created
            t.create(record)
            t.edit_before(host_ip_address, reverse_dns_record_id: nil)
          else
            t.edit_before(record, content: record.content_was)
          end

          t.just_create(log)
        end
      end

      record.save!
      host_ip_address.save!
      host_ip_address
    end
  end
end
