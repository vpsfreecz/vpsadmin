module TransactionChains
  class Vps::ShaperChange < ::TransactionChain
    label 'Change shaper'

    def link_chain(ip, tx, rx)
      lock(ip.vps)
      lock(ip)

      append(Transactions::Vps::ShaperChange, args: [ip, tx, rx]) do
        edit(ip, max_tx: tx, max_rx: rx)
      end
    end
  end
end
