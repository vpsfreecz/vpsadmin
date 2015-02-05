module TransactionChains
  class Ip::Free < ::TransactionChain
    label 'Free IP from object'

    def free_from_vps(r, vps)
      v = r.name == 'ipv4' ? 4 : 6

      vps.ip_addresses.where(ip_v: v).each do |ip|
        lock(ip)

        append(Transactions::Vps::IpDel, args: [vps, ip]) do
          edit(ip, vps_id: nil)
        end
      end
    end
  end
end
