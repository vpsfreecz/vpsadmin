module TransactionChains
  class Dataset::Snapshot < ::TransactionChain
    label 'Snapshot'

    # @param dataset_in_pool [DatasetInPool]
    # @param opts [Hash] options
    # @option opts [String] label user-friendly snapshot label
    def link_chain(dataset_in_pool, opts = {})
      # The provisional Snapshot is inserted before append checks admission.
      StorageMutationAdmission.check!
      lock(dataset_in_pool)
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      snap = next_snapshot_name(dataset_in_pool.dataset_id)

      s = ::Snapshot.create!(
        name: "#{snap} (unconfirmed)",
        dataset_id: dataset_in_pool.dataset_id,
        history_id: dataset_in_pool.dataset.current_history_id,
        label: opts[:label],
        confirmed: ::Snapshot.confirmed(:confirm_create)
      )

      sip = ::SnapshotInPool.create!(
        snapshot: s,
        dataset_in_pool:,
        confirmed: ::SnapshotInPool.confirmed(:confirm_create)
      )

      append(Transactions::Storage::CreateSnapshot, args: sip) do
        create(s)
        create(sip)
      end

      sip
    end

    private

    def next_snapshot_name(dataset_id)
      # Serialize allocations for this logical Dataset until staging commits.
      ::Dataset.lock.find(dataset_id)
      candidate = Time.now.utc

      60.times do
        name = candidate.strftime('%Y-%m-%dT%H:%M:%S')
        # A locking read sees rows committed while this transaction waited for
        # admission or the Dataset lock, even with REPEATABLE READ.
        existing = ::Snapshot.where(dataset_id:, name: [name, "#{name} (unconfirmed)"])
                             .lock.limit(1).pick(:id)
        return name unless existing

        candidate += 1
      end

      raise 'unable to allocate snapshot name within 60 seconds'
    end
  end
end
