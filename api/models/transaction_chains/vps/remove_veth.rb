module TransactionChains
  class Vps::RemoveVeth < ::TransactionChain
    label 'Veth-'

    def link_chain(vps)
      # Remove veth interface
      append_t(Transactions::Vps::RemoveVeth, args: vps) do |t|
        t.edit(vps, veth_mac: nil)
      end
    end
  end
end
