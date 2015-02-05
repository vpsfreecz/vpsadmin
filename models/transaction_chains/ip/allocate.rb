module TransactionChains
  class Ip::Allocate < ::TransactionChain
    label 'Allocate IP to object'

    def allocate_to_vps(r, vps, n)
      ips = []
      v = r.name == 'ipv4' ? 4 : 6

      loop do
        begin
          ::IpAddress.transaction do
            ip = ::IpAddress.pick_addr!(vps.user, vps.node.location, v)
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

      ips.each do |ip|
        append(Transactions::Vps::IpAdd, args: [vps, ip]) do
          edit(ip, vps_id: vps.veid)
          edit(ip, user_id: vps.user_id) unless ip.user_id
        end
      end

      ips.size
    end
  end
end
