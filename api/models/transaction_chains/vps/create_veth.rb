module TransactionChains
  class Vps::CreateVeth < ::TransactionChain
    label 'Veth+'

    def link_chain(vps)
      # Assign interconneting networks for routed veth
      interconnecting_ips = Hash[ [4, 6].map { |v| [v, get_ip(vps, v)] } ]

      # Create veth interface
      append_t(Transactions::Vps::CreateVeth, args: [vps, interconnecting_ips]) do |t|
        interconnecting_ips.each_value do |ip|
          t.edit_before(ip, vps_id: ip.vps_id, order: ip.order)

          ip.update!(
              vps_id: vps.id,
              order: 0, # interconnecting IPs are always first
          )
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
