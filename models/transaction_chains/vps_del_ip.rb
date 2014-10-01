module TransactionChains
  class VpsDelIp < ::TransactionChain
    def link_chain(vps, ips)
      ips.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpDel, args: [vps, ip]) do
          edit(ip, vps_id: nil)
        end
      end
    end
  end
end
