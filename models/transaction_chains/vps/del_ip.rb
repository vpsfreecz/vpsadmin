module TransactionChains
  class Vps::DelIp < ::TransactionChain
    label 'IP-'

    def link_chain(vps, ips, resource_obj = nil, unregister = true,
                   reallocate = true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      resource_obj ||= vps

      uses = []
      
      if reallocate
        {ipv4: 4, ipv6: 6}.each do |r, v|
          cnt = ips.count { |ip| ip.network.ip_version == v }

          uses << resource_obj.reallocate_resource!(r, resource_obj.send(r) - cnt, user: vps.user)
        end
      end

      chain = self

      ips.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpDel, args: [vps, ip, unregister]) do
          edit(ip, vps_id: nil)
          just_create(vps.log(:ip_del, {id: ip.id, addr: ip.addr})) unless chain.included?
        end
      end

      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        uses.each do |use|
          edit(use, value: use.value)
        end
      end unless uses.empty?
    end
  end
end
