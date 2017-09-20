module TransactionChains::Maintenance
  class Custom < ::TransactionChain
    label 'Custom'

    def link_chain(*args)
      raise NotImplementedError
    end
  end
end
