module TransactionChains
  class Vps::DelIp < ::TransactionChain
    label 'Delete IP address'

    def link_chain(vps, ips)
      use = vps.reallocate_resource!(:ipv4, vps.ipv4 - ips.size, user: vps.user)

      ips.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpDel, args: [vps, ip]) do
          edit(ip, vps_id: nil)
        end
      end

      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        edit(use, value: use.value)
      end
    end
  end
end
