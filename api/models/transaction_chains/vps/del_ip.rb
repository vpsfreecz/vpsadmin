module TransactionChains
  class Vps::DelIp < ::TransactionChain
    label 'IP-'

    def link_chain(vps, ips, resource_obj = nil, unregister = true,
                   reallocate = true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      resource_obj ||= vps

      uses = []
      user_env = vps.user.environment_user_configs.find_by!(
          environment: vps.node.location.environment,
      )
      ips_arr = ips.to_a

      if reallocate && !vps.node.location.environment.user_ip_ownership
        %i(ipv4 ipv4_private ipv6).each do |r|
          cnt = case r
          when :ipv4
            ips_arr.inject(0) do |sum, ip|
              if ip.network.role == 'public_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv4_private
            ips_arr.inject(0) do |sum, ip|
              if ip.network.role == 'private_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv6
            ips_arr.inject(0) do |sum, ip|
              if ip.network.ip_version == 6
                sum + ip.size

              else
                sum
              end
            end
          end

          uses << user_env.reallocate_resource!(
              r,
              user_env.send(r) - cnt,
              user: vps.user
          )
        end
      end

      chain = self

      ips_arr.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpDel, args: [vps, ip, unregister]) do
          edit(ip, vps_id: nil, order: nil)
          just_create(vps.log(:ip_del, {id: ip.id, addr: ip.addr})) unless chain.included?
        end
      end

      append(Transactions::Utils::NoOp, args: vps.node_id) do
        uses.each do |use|
          edit(use, value: use.value)
        end
      end unless uses.empty?
    end
  end
end
