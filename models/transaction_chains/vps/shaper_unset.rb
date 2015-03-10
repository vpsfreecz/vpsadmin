module TransactionChains
  class Vps::ShaperUnset < ::TransactionChain
    label 'Unset shaper'

    def link_chain(vps)
      set_concerns(:affect, [vps.class.name, vps.id])

      vps.ip_addresses.all.each do |ip|
        lock(ip)

        append(Transactions::Shaper::Unset, args: [ip, vps])
      end
    end
  end
end
