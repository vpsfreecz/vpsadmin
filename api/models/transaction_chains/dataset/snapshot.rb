module TransactionChains
  class Dataset::Snapshot < ::TransactionChain
    label 'Snapshot'
    allow_empty

    # @param dataset_in_pool [DatasetInPool]
    # @param opts [Hash] options
    # @option opts [String] label user-friendly snapshot label
    def link_chain(dataset_in_pool, opts = {})
      lock(dataset_in_pool)
      if opts[:expected_action] && !::DatasetAction.scheduled_for?(opts[:expected_action], action: :snapshot, source: dataset_in_pool)
        return
      end

      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      snap = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S')

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
  end
end
