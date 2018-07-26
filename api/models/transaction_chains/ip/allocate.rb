module TransactionChains
  class Ip::Allocate < ::TransactionChain
    label 'Allocate IP to object'

    def allocate_to_environment_user_config(r, vps, n)
      return n if n == 0
      raise NotImplementedError
    end

    def allocate_to_netif(r, netif, n, strict: true)
      return n if n == 0

      ips = []
      v = r.name == 'ipv6' ? 6 : 4

      loop do
        begin
          ::IpAddress.transaction do
            ip = ::IpAddress.pick_addr!(
              netif.vps.user,
              netif.vps.node.location,
              v,
              r.name.end_with?('_private') ? :private_access : :public_access,
            )
            lock(ip)

            ips << ip
          end

        rescue ActiveRecord::RecordNotFound
          if strict
            fail "no #{r.name} available"

          else
            break
          end

        rescue ResourceLocked
          sleep(0.25)
          retry
        end

        break if ips.size == n
      end

      chowned = 0
      ownership = netif.vps.node.location.environment.user_ip_ownership
      last_ip = netif.ip_addresses.joins(:network).where(
        networks: {ip_version: v}
      ).order('`order` DESC').take

      order = last_ip ? last_ip.order + 1 : 0

      ips.each do |ip|
        append_t(Transactions::NetworkInterface::AddRoute, args: [netif, ip]) do |t|
          t.edit_before(
            ip,
            network_interface_id: ip.network_interface_id,
            order: ip.order,
          )
          t.edit_before(ip, user_id: ip.user_id) if ownership
        end

        ip.network_interface_id = netif.id
        ip.order = order

        chowned += ip.size if (!ip.user_id && ownership) || !ownership
        ip.user_id = netif.vps.user_id if !ip.user_id && ownership

        ip.save!

        order += 1
      end

      chowned
    end
  end
end
