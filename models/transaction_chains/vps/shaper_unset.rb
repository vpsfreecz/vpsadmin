module TransactionChains
  class Vps::ShaperUnset < ::TransactionChain
    label 'Unset shaper'

    def link_chain(vps)
      vps.ip_addresses.all.each do |ip|
        lock(ip)

        append(Transactions::Shaper::Unset, args: [ip, vps])
      end
    end
  end
end
