module TransactionChains
  class Vps::DelIp < ::TransactionChain
    label 'IP-'

    def link_chain(vps, ips, resource_obj = nil, unregister = true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      resource_obj ||= vps

      uses = []

      {ipv4: 4, ipv6: 6}.each do |r, v|
        cnt = ips.count { |ip| ip.ip_v == v }

        uses << resource_obj.reallocate_resource!(r, resource_obj.send(r) - cnt, user: vps.user)
      end

      ips.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpDel, args: [vps, ip, unregister]) do
          edit(ip, vps_id: nil)
        end
      end

      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        uses.each do |use|
          edit(use, value: use.value)
        end
      end
    end
  end
end
