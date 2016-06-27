module TransactionChains
  class Ip::Free < ::TransactionChain
    label 'Free IP from object'

    def free_from_vps(r, vps)
      v = r.name == 'ipv6' ? 6 : 4

      vps.ip_addresses.joins(:network).where(networks: {
          ip_version: v,
          role: ::Network.roles[ r.name.end_with?('_private') ? :private_access : :public_access ]
      }).each do |ip|
        lock(ip)

        append(Transactions::Vps::IpDel, args: [vps, ip]) do
          edit(ip, vps_id: nil)
        end
      end
    end
  end
end
