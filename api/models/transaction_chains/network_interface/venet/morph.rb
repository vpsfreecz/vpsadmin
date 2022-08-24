require_relative '../veth/helpers'

module TransactionChains
  class NetworkInterface::Venet::Morph < ::TransactionChain
    label 'Morph'

    include NetworkInterface::Veth::Helpers

    # @param netif [::NetworkInterface]
    # @param target_netif_type [Symbol]
    def link_chain(netif, target_netif_type)
      orig_kind = netif.kind

      ret = send(:"into_#{target_netif_type}", netif)

      ret.call_class_hooks_for(
        :morph,
        self,
        args: [ret, orig_kind, ret.kind],
      )

      ret
    end

    protected
    def into_veth_routed(netif)
      orig_kind = netif.kind

      update_unique do
        netif.update!(
          kind: 'veth_routed',
          mac: gen_mac,
        )
      end

      append_t(
        Transactions::NetworkInterface::CreateVethRouted,
        args: netif
      ) do |t|
        t.edit_before(
          netif,
          kind: ::NetworkInterface.kinds[orig_kind],
          mac: nil,
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
