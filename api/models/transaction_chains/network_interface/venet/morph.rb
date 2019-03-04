require_relative '../veth/helpers'

module TransactionChains
  class NetworkInterface::Venet::Morph < ::TransactionChain
    label 'Morph'

    include NetworkInterface::Veth::Helpers

    # @param netif [::NetworkInterface]
    # @param target_netif_type [Symbol]
    def link_chain(netif, target_netif_type)
      send(:"into_#{target_netif_type}", netif)
    end

    protected
    def into_veth_routed(netif)
      append_t(
        Transactions::NetworkInterface::CreateVethRouted,
        args: netif
      ) do |t|
        t.edit_before(
          netif,
          kind: ::NetworkInterface.kinds[netif.kind],
          mac: nil,
        )
      end

      update_unique do
        netif.update!(
          kind: 'veth_routed',
          mac: gen_mac,
        )
      end

      netif
    end

    def update_unique
      5.times do
        begin
          return yield

        rescue ActiveRecord::RecordNotUnique
          sleep(0.25)
          next
        end
      end

      fail 'unable to generate a unique mac address'
    end
  end
end
