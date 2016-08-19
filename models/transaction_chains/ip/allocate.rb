module TransactionChains
  class Ip::Allocate < ::TransactionChain
    label 'Allocate IP to object'

    def allocate_to_vps(r, vps, n)
      return n if n == 0

      ips = []
      v = r.name == 'ipv6' ? 6 : 4

      loop do
        begin
          ::IpAddress.transaction do
            ip = ::IpAddress.pick_addr!(
                vps.user,
                vps.node.location,
                v,
                r.name.end_with?('_private') ? :private_access : :public_access,
            )
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

      order = 0

      ips.each do |ip|
        ownership = !ip.user_id && vps.node.location.environment.user_ip_ownership

        append(Transactions::Vps::IpAdd, args: [vps, ip]) do
          edit_before(ip, vps_id: ip.vps_id, order: order)
          edit_before(ip, user_id: ip.user_id) if ownership
        end
        
        ip.vps_id = vps.id
        ip.user_id = vps.m_id if ownership
        ip.save!

        order += 1
      end

      ips.size
    end
  end
end
