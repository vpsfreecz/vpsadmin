module TransactionChains
  # Unset reverse records and delete user-created host IP addresses
  class NetworkInterface::CleanupHostIpAddresses < ::TransactionChain
    label 'Cleanup host IPs'

    # @param ips [Array<::IpAddress>]
    # @param delete [Boolean] delete user-created host IP addresses
    def link_chain(ips:, delete:)
      return unless delete

      to_delete = []

      ips.each do |ip|
        lock(ip)

        ip.host_ip_addresses.each do |host|
          use_chain(DnsZone::UnsetReverseRecord, args: [host]) if host.reverse_dns_record
          to_delete << host if host.user_created
        end
      end

      return if to_delete.empty?

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        to_delete.each do |host|
          t.just_destroy(host)
        end
      end
    end
  end
end
