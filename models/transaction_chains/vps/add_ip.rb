module TransactionChains
  class Vps::AddIp < ::TransactionChain
    label 'Add IP address'

    def link_chain(vps, ips)
      use = vps.reallocate_resource!(:ipv4, vps.ipv4 + ips.size, user: vps.user)

      ips.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpAdd, args: [vps, ip]) do
          edit(ip, vps_id: vps.veid)
        end
      end

      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        edit(use, value: use.value)
      end
    end
  end
end
