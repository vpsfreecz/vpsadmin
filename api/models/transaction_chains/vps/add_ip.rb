module TransactionChains
  class Vps::AddIp < ::TransactionChain
    label 'IP+'

    def link_chain(vps, ips, register = true, reallocate = true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      if vps.node.openvz? && ips.detect { |ip| ip.size > 1 }
        raise VpsAdmin::API::Exceptions::NotAvailableOnOpenVz,
              "cannot add IP address with prefix other than /32 or /128"
      end

      uses = []
      user_env = vps.user.environment_user_configs.find_by!(
        environment: vps.node.location.environment,
      )
      ownership = vps.node.location.environment.user_ip_ownership
      ips_arr = ips.to_a

      if reallocate
        %i(ipv4 ipv4_private ipv6).each do |r|
          cnt = case r
          when :ipv4
            ips_arr.inject(0) do |sum, ip|
              if (!ownership || ip.user.nil?) \
                 && ip.network.role == 'public_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv4_private
            ips_arr.inject(0) do |sum, ip|
              if (!ownership || ip.user.nil?) \
                 && ip.network.role == 'private_access' && ip.network.ip_version == 4
                sum + ip.size

              else
                sum
              end
            end

          when :ipv6
            ips_arr.inject(0) do |sum, ip|
              if (!ownership || ip.user.nil?) && ip.network.ip_version == 6
                sum + ip.size

              else
                sum
              end
            end
          end

          cur = user_env.send(r)

          uses << user_env.reallocate_resource!(
            r,
            cur + cnt,
            user: vps.user
          ) if cnt != 0
        end
      end

      chain = self
      order = {}
      [4, 6].each do |v|
        last_ip = vps.ip_addresses.joins(:network).where(
          networks: {ip_version: v}
        ).order('`order` DESC').take

        order[v] = last_ip ? last_ip.order + 1 : 0
      end

      ips_arr.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpAdd, args: [vps, ip, register]) do
          edit(ip, vps_id: vps.veid, order: order[ip.version])
          edit(ip, user_id: vps.user_id) if ownership && !ip.user_id

          just_create(vps.log(:ip_add, {id: ip.id, addr: ip.addr})) unless chain.included?
        end

        order[ip.version] += 1
      end

      append(Transactions::Utils::NoOp, args: vps.node_id) do
        uses.each do |use|
          if use.updating?
            edit(use, value: use.value)
          else
            create(use)
          end
        end
      end unless uses.empty?
    end
  end
end
