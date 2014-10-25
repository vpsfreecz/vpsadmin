module TransactionChains
  # Encapsulates both Dataset::Snapshot and Dataset::Transfer.
  class Dataset::Backup < ::TransactionChain
    label 'Backup dataset'

    def link_chain(src_dataset_in_pool, dst_dataset_in_pool)
      lock(src_dataset_in_pool)
      lock(dst_dataset_in_pool)

      use_chain(Dataset::Snapshot, src_dataset_in_pool)

      # The transfer transaction MUST retrieve the snapshot name before
      # execution (on vpsAdmind), because it may be different!
      # That is not very nice and should be solved better in the future.
      use_chain(Dataset::Transfer, src_dataset_in_pool, dst_dataset_in_pool)
    end
  end
end
