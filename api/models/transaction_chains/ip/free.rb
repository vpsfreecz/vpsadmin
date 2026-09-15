module TransactionChains
  class Ip::Free < ::TransactionChain
    label 'Free IP from object'

    def free_from_environment_user_config(r, user_env)
      v = r.name == 'ipv6' ? 6 : 4
      ips = []

      ::IpAddress.joins(:network).where(
        user: user_env.user,
        charged_environment_id: [nil, user_env.environment_id],
        networks: {
          ip_version: v,
          role: ::Network.roles[
            r.name.end_with?('_private') ? :private_access : :public_access
          ]
        }
      ).order(:id).each do |ip|
        ip.lock_current!(self)
        next unless ip.user_id == user_env.user_id

        ip.ensure_charge_environment!
        next unless ip.charged_environment_id == user_env.environment_id

        ips << ip
      end

      return if ips.empty?

      use_chain(NetworkInterface::CleanupHostIpAddresses, kwargs: { ips:, delete: true })

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        ips.each do |ip|
          t.edit(ip, user_id: nil, charged_environment_id: nil)
        end
      end
    end
  end
end
