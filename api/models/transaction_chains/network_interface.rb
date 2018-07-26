module TransactionChains
  module NetworkInterface
    TYPES = {
      venet: Venet,
      veth_routed: VethRouted,
    }

    def self.chain_for(type, action)
      TYPES[type.to_sym].const_get(action)
    end
  end
end
