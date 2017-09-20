module TransactionChains
  class Lifetimes::NotImplemented < ::TransactionChain
    def link_chain(obj, target, state, log)
      raise NotImplementedError,
            "Transition to state '#{state}' is not implemented"
    end
  end
end
