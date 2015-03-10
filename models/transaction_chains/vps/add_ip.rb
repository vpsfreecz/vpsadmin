module TransactionChains
  class Vps::AddIp < ::TransactionChain
    label 'IP+'

    def link_chain(vps, ips)
      lock(vps)
      set_concerns(:affect, [vps.class.name, vps.id])

      use = vps.reallocate_resource!(:ipv4, vps.ipv4 + ips.size, user: vps.user)

      ips.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpAdd, args: [vps, ip]) do
          edit(ip, vps_id: vps.veid)
          edit(ip, user_id: vps.user_id)  if !ip.user_id && vps.node.environment.user_ip_ownership
        end
      end

      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        edit(use, value: use.value)
      end
    end
  end
end
