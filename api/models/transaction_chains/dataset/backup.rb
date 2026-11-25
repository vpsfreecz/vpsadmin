module TransactionChains
  # Encapsulates both Dataset::Snapshot and Dataset::Transfer.
  class Dataset::Backup < ::TransactionChain
    label 'Backup'
    allow_empty

    def link_chain(src_dataset_in_pool, dst_dataset_in_pool, expected_action: nil)
      lock(src_dataset_in_pool)
      lock(dst_dataset_in_pool)

      if expected_action && !::DatasetAction.scheduled_for?(expected_action, action: :backup, source: src_dataset_in_pool, destination: dst_dataset_in_pool)
        return
      end

      concerns(:affect, [
                 src_dataset_in_pool.dataset.class.name,
                 src_dataset_in_pool.dataset_id
               ])

      # The transfer transaction MUST retrieve the snapshot name before
      # execution (on vpsAdmind), because it may be different!
      # That is not very nice and should be solved better in the future.
      use_chain(
        Dataset::Transfer,
        args: [src_dataset_in_pool, dst_dataset_in_pool],
        kwargs: { send_reservation: true },
        prio: -10
      )

      use_chain(Dataset::Rotate, args: src_dataset_in_pool, prio: -10)
      use_chain(Dataset::Rotate, args: dst_dataset_in_pool)
    end
  end
end
