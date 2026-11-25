module TransactionChains
  class Dataset::GroupSnapshot < ::TransactionChain
    label 'Snapshot dataset'
    allow_empty

    def link_chain(dataset_in_pools, opts = {})
      snap = Time.new.strftime('%Y-%m-%dT%H:%M:%S')
      snapshots = []

      dataset_in_pools.each do |dip|
        if opts[:strict]
          lock(dip)
        else
          begin
            lock(dip)
          rescue ResourceLocked
            warn "dataset #{dip.id} is locked, skipping"
            next
          end
        end

        if opts[:expected_action] && !::DatasetAction.scheduled_for?(opts[:expected_action], action: :group_snapshot, source: dip)
          next
        end

        s = ::Snapshot.create!(
          name: "#{snap} (unconfirmed)",
          dataset_id: dip.dataset_id,
          history_id: dip.dataset.current_history_id,
          label: opts[:label],
          confirmed: ::Snapshot.confirmed(:confirm_create)
        )

        sip = ::SnapshotInPool.create!(
          snapshot: s,
          dataset_in_pool: dip,
          confirmed: ::SnapshotInPool.confirmed(:confirm_create)
        )

        snapshots << sip
      end

      return snapshots if snapshots.empty?

      append(
        Transactions::Storage::CreateSnapshots,
        args: [snapshots]
      ) do
        snapshots.each do |sip|
          create(sip.snapshot)
          create(sip)
        end
      end

      snapshots
    end
  end
end
