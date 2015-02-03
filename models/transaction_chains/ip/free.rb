module TransactionChains
  class Ip::Free < ::TransactionChain
    label 'Free IP from object'

    def free_from_vps(r, vps)
      v = r.name == 'ipv4' ? 4 : 6

      use_chain(Vps::DelIp, args: [vps, vps.ip_addresses.where(ip_v: v)])
    end
  end
end
