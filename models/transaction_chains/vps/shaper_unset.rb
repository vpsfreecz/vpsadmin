module TransactionChains
  class Vps::ShaperUnset < ::TransactionChain
    label 'Shaper-'

    def link_chain(vps)
      concerns(:affect, [vps.class.name, vps.id])

      vps.ip_addresses.all.each do |ip|
        lock(ip)

        append(Transactions::Shaper::Unset, args: [ip, vps])
      end
    end
  end
end
