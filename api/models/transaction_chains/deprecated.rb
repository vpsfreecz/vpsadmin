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

    module Clone
      class VzToOs < Deprecated
        label 'Clone'
      end

      class VzToVz < Deprecated
        label 'Clone'
      end
    end

    module Migrate
      class OsToVz < Deprecated
        label 'Migrate'
      end

      class VzToOs < Deprecated
        label 'Migrate'
      end

      class VzToVz < Deprecated
        label 'Migrate'
      end
    end
  end
end
