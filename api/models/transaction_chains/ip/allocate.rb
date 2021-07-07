module TransactionChains
  class Ip::Allocate < ::TransactionChain
    label 'Allocate IP to object'

    def allocate_to_environment_user_config(r, vps, n)
      return n if n == 0
      raise NotImplementedError
    end

    def allocate_to_netif(r, netif, n, strict: true, host_addrs: false, address_location: nil)
      return n if n == 0

      ips = []
      v = r.name == 'ipv6' ? 6 : 4

      loop do
        begin
          ::IpAddress.transaction do
            ip = ::IpAddress.pick_addr!(
              user: netif.vps.user,
              location: netif.vps.node.location,
              ip_v: v,
              role: r.name.end_with?('_private') ? :private_access : :public_access,
              purpose: :vps,
              address_location: address_location,
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
      ).order(order: :desc).take

      order = last_ip ? last_ip.order + 1 : 0

      ips.each do |ip|
        append_t(Transactions::NetworkInterface::AddRoute, args: [netif, ip]) do |t|
          t.edit_before(
            ip,
            network_interface_id: ip.network_interface_id,
            order: ip.order,
            charged_environment_id: ip.charged_environment_id,
          )
          t.edit_before(ip, user_id: ip.user_id) if ownership
        end

        ip.network_interface_id = netif.id
        ip.order = order
        ip.charged_environment_id = netif.vps.node.location.environment_id

        chowned += ip.size if (!ip.user_id && ownership) || !ownership
        ip.user_id = netif.vps.user_id if !ip.user_id && ownership

        ip.save!

        if host_addrs
          use_chain(
            NetworkInterface::AddHostIp,
            args: [netif, ip.host_ip_addresses.where(auto_add: true), check_addrs: false]
          )
        end

        order += 1
      end

      use_chain(Export::AddHostsToAll, args: [netif.vps.user, ips])

      chowned
    end
  end
end
