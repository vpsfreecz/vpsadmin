module TransactionChains
  class Ip::Allocate < ::TransactionChain
    label 'Allocate IP to object'

    def allocate_to_vps(r, vps, n)
      ips = []
      v = r.name == 'ipv4' ? 4 : 6

      loop do
        begin
          ::IpAddress.transaction do
            ip = ::IpAddress.pick_addr!(vps.node.location, v)
            lock(ip)

            ips << ip
          end

        rescue ActiveRecord::RecordNotFound
          fail "no #{r.name} available"

        rescue ResourceLocked
          sleep(0.25)
          retry
        end

        break if ips.size == n
      end

      use_chain(Vps::AddIp, args: [vps, ips])

      ips.size
    end

    def free_from_vps(r, vps)
      ips = vps.ip_addresses.where(ip_v: r.name == 'ipv4' ? 4 : 6)

      use_chain(Vps::DelIp, args: [vps, ips])
    end
  end
end
