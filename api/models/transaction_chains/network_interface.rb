module TransactionChains
  module NetworkInterface
    TYPES = {
      veth_routed: VethRouted
    }.freeze

    def self.chain_for(type, action)
      TYPES[type.to_sym].const_get(action)
    end
  end
end
