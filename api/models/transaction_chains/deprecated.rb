module TransactionChains
  class Deprecated < ::TransactionChain
    def link_chain(*_)
      fail "Transaction chain #{self.class.name} has been deprecated"
    end
  end

  module Vps
    class AddIp < Deprecated ; end
    class DelIp < Deprecated ; end
    class CreateVeth < Deprecated ; end
    class RemoveVeth < Deprecated ; end
  end
end
