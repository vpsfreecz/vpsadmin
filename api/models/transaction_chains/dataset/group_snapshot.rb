module TransactionChains
  class Dataset::GroupSnapshot < ::TransactionChain
    label 'Snapshot dataset'

    def link_chain(dataset_in_pools)
      snap = Time.new.strftime('%Y-%m-%dT%H:%M:%S')
      snapshots = []

      dataset_in_pools.each do |dip|
        begin
          lock(dip)

        rescue ResourceLocked
          warn "dataset #{dip.id} is locked, skipping"
          next
        end

        s = ::Snapshot.create!(
            name: "#{snap} (unconfirmed)",
            dataset_id: dip.dataset_id,
            confirmed: ::Snapshot.confirmed(:confirm_create)
        )

        sip = ::SnapshotInPool.create!(
            snapshot: s,
            dataset_in_pool: dip,
            confirmed: ::SnapshotInPool.confirmed(:confirm_create)
        )

        snapshots << sip
      end

      append(Transactions::Storage::CreateSnapshots, args: [snapshots]) do
        snapshots.each do |sip|
          create(sip.snapshot)
          create(sip)
        end
      end
    end
  end
end
