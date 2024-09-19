module TransactionChains
  class Ip::Free < ::TransactionChain
    label 'Free IP from object'

    def free_from_environment_user_config(r, user_env)
      v = r.name == 'ipv6' ? 6 : 4
      ips = []

      ::IpAddress.joins(network: { location_networks: :location }).where(
        user: user_env.user,
        networks: {
          ip_version: v,
          role: ::Network.roles[
            r.name.end_with?('_private') ? :private_access : :public_access
          ]
        },
        locations: {
          environment_id: user_env.environment_id
        }
      ).each do |ip|
        lock(ip)
        ips << ip
      end

      return if ips.empty?

      ips.each do |ip|
        ip.host_ip_addresses.each do |host_ip|
          host_ip.dns_zone_transfers.each do |zone_transfer|
            use_chain(DnsZoneTransfer::Destroy, args: [zone_transfer])
          end
        end
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        ips.each do |ip|
          t.edit(ip, user_id: nil, charged_environment_id: nil)
        end
      end

      use_chain(NetworkInterface::CleanupHostIpAddresses, kwargs: { ips:, delete: true })
    end
  end
end
