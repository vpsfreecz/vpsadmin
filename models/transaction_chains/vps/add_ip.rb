module TransactionChains
  class Vps::AddIp < ::TransactionChain
    label 'IP+'

    def link_chain(vps, ips, register = true, reallocate = true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      uses = []

      if reallocate
        {ipv4: 4, ipv6: 6}.each do |r, v|
          cnt = ips.count { |ip| ip.network.ip_version == v }

          uses << vps.reallocate_resource!(r, vps.send(r) + cnt, user: vps.user)
        end
      end

      chain = self

      ips.each do |ip|
        lock(ip)

        append(Transactions::Vps::IpAdd, args: [vps, ip, register]) do
          edit(ip, vps_id: vps.veid)
          edit(ip, user_id: vps.user_id)  if !ip.user_id && vps.node.environment.user_ip_ownership

          just_create(vps.log(:ip_add, {id: ip.id, addr: ip.addr})) unless chain.included?
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
