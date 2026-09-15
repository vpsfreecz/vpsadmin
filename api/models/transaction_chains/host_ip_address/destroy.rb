module TransactionChains
  class HostIpAddress::Destroy < ::TransactionChain
    label 'Host IP-'
    allow_empty

    # @param host_ip_address [::HostIpAddress]
    def link_chain(host_ip_address, actor: nil)
      host_ip_address.lock_with_ip!(self, actor:)
      if actor && (!host_ip_address.user_created || host_ip_address.assigned?)
        raise VpsAdmin::API::Exceptions::OperationError, "#{host_ip_address.ip_addr} cannot be deleted"
      end

      concerns(
        :affect,
        [host_ip_address.class.name, host_ip_address.id]
      )

      host_ip_address.remove_dns_transfers!(self)
      use_chain(DnsZone::UnsetReverseRecord, args: [host_ip_address]) if host_ip_address.reverse_dns_record

      if empty?
        host_ip_address.destroy!
        return
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_destroy(host_ip_address)
      end

      nil
    end
  end
end
