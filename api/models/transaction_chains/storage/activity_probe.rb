module TransactionChains
  module Storage
    class ActivityProbe < ::TransactionChain
      label 'Storage activity probe'

      def link_chain(request)
        append(Transactions::Storage::ActivityProbe, args: [request])
      end
    end
  end
end
