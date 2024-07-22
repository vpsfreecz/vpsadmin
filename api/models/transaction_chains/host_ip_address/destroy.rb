module TransactionChains
  class HostIpAddress::Destroy < ::TransactionChain
    label 'Host IP-'
    allow_empty

    # @param host_ip_address [::HostIpAddress]
    def link_chain(host_ip_address)
      lock(host_ip_address)

      concerns(
        :affect,
        [host_ip_address.class.name, host_ip_address.id]
      )

      if host_ip_address.reverse_dns_record.nil?
        host_ip_address.destroy!
        return
      end

      use_chain(DnsZone::UnsetReverseRecord, args: [host_ip_address])

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_destroy(host_ip_address)
      end

      nil
    end
  end
end
