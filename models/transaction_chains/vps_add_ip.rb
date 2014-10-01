module TransactionChains
  class VpsAddIp < ::TransactionChain
    def link_chain(vps, ips)
      ips.each do |ip|
        append(Transactions::Vps::IpAdd, args: [vps, ip]) do
          edit(ip, vps_id: vps.veid)
        end
      end
    end
  end
end
