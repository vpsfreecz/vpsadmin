module TransactionChains
  # Encapsulates both DatasetSnapshot and DatasetTransfer.
  class DatasetBackup < ::TransactionChain
    label 'Backup dataset'

    def link_chain(src_dataset_in_pool, dst_dataset_in_pool)
      lock(src_dataset_in_pool)
      lock(dst_dataset_in_pool)

      use_chain(DatasetSnapshot, src_dataset_in_pool)

      # The transfer transaction MUST retrieve the snapshot name before
      # execution (on vpsAdmind), because it may be different!
      # That is not very nice and should be solved better in the future.
      use_chain(DatasetTransfer, src_dataset_in_pool, dst_dataset_in_pool)
    end
  end
end
