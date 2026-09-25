module TransactionChains
  module Storage
    class Inventory < ::TransactionChain
      label 'Storage inventory'

      def link_chain(request)
        append(Transactions::Storage::Inventory, args: [request])
      end
    end
  end
end
