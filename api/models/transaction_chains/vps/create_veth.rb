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

          t.edit_before(vps, veth_mac: nil)
          gen_unique_mac(vps)
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

    def gen_unique_mac(vps)
      5.times do
        mac = gen_mac

        begin
          vps.update!(veth_mac: mac)

        rescue ActiveRecord::RecordNotUnique
          sleep(0.25)
          next
        end
      end

      if vps.veth_mac.nil?
        fail 'unable to generate unique mac address'
      end
    end

    def gen_mac
      # First three octets -- OUI
      octets = (1..3).map { rand(256) }

      # Mark as locally administered
      octets[0] &= 0xfe
      octets[0] |= 0x02

      # Last three octets -- NIC
      3.times { octets << rand(256) }

      octets.map { |v| '%02x' % [v] }.join(':')
    end
  end
end
