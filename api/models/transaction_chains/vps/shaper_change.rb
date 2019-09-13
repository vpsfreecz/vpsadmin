module TransactionChains
  class Vps::ShaperChange < ::TransactionChain
    label 'Shaper*'

    def link_chain(ip, tx, rx)
      lock(ip.network_interface)
      lock(ip.network_interface.vps)
      lock(ip)
      concerns(:affect, [
        ip.network_interface.vps.class.name,
        ip.network_interface.vps.id
      ])

      append(Transactions::Vps::ShaperChange, args: [ip, tx, rx]) do
        edit(ip, max_tx: tx, max_rx: rx)
      end
    end
  end
end
