module TransactionChains
  class StorageVolume::Destroy < ::TransactionChain
    label 'Destroy'

    def link_chain(storage_vol)
      lock(storage_vol)

      append_t(Transactions::StorageVolume::Destroy, args: [storage_vol]) do |t|
        t.destroy(storage_vol)
      end

      nil
    end
  end
end
