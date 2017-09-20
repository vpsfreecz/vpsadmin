module TransactionChains
  class Ip::Free < ::TransactionChain
    label 'Free IP from object'

    def free_from_environment_user_config(r, user_env)
      v = r.name == 'ipv6' ? 6 : 4
      ips = []
      
      ::IpAddress.joins(network: :location).where(
          user: user_env.user,
          networks: {
              ip_version: v,
              role: ::Network.roles[
                  r.name.end_with?('_private') ? :private_access : :public_access
              ],
          },
          locations: {
              environment_id: user_env.environment_id,
          }
      ).each do |ip|
        lock(ip)
        ips << ip
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        ips.each { |ip| t.edit(ip, user_id: nil) }
      end unless ips.empty?
    end
  end
end
