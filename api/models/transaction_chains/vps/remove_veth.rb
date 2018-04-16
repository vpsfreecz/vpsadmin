module TransactionChains
  class Vps::RemoveVeth < ::TransactionChain
    label 'Veth-'

    def link_chain(vps)
      # Find interconneting networks for routed veth.
      # This is needed in case this action needs to be rolled back and the veth
      # recreated.
      interconnecting_ips = {}

      ::IpAddress.joins(:network).where(
          networks: {role: ::Network.roles[:interconnecting]},
          vps_id: vps.id
      ).each do |ip|
        fail "shouldn't happen" if interconnecting_ips[ip.network.ip_version]
        interconnecting_ips[ip.network.ip_version] = ip

        lock(ip)
      end

      # Remove veth interface
      append_t(Transactions::Vps::RemoveVeth, args: [vps, interconnecting_ips]) do |t|
        interconnecting_ips.each_value do |ip|
          t.edit(ip, vps_id: nil)
        end
      end
    end

    protected
    def get_ip(vps, version)
      ::IpAddress.transaction do
        ip = ::IpAddress.pick_addr!(
          vps.user,
          vps.node.location,
          version,
          :interconnecting
        )

        lock(ip)

        return ip
      end

    rescue ActiveRecord::RecordNotFound
      # TODO: we could automatically add new addresses to existing networks
      #   that aren't fully utilized and have managed = true.
      fail "no interconnecting network for IPv#{version} found"

    rescue ResourceLocked
      sleep(0.25)
      retry
    end
  end
end
