module TransactionChains
  class Vps::FirewallRegister < ::TransactionChain
    label 'Firewall+'

    def link_chain(vps, ips = nil)
      concerns(:affect, [vps.class.name, vps.id])

      (ips || vps.ip_addresses.all).each do |ip|
        lock(ip)

        append(Transactions::Firewall::RegIp, args: [ip, vps])
      end
    end
  end
end
