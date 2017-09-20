module TransactionChains
  class Vps::FirewallUnregister < ::TransactionChain
    label 'Firewall-'

    def link_chain(vps)
      concerns(:affect, [vps.class.name, vps.id])

      vps.ip_addresses.all.each do |ip|
        lock(ip)

        append(Transactions::Firewall::UnregIp, args: [ip, vps])
      end
    end
  end
end
