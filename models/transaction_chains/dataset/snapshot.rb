module TransactionChains
  class Dataset::Snapshot < ::TransactionChain
    label 'Snapshot'

    def link_chain(dataset_in_pool)
      lock(dataset_in_pool)
      concerns(:affect, [dataset_in_pool.dataset.class.name, dataset_in_pool.dataset_id])

      snap = Time.new.strftime('%Y-%m-%dT%H:%M:%S')

      s = ::Snapshot.create(
          name: "#{snap} (unconfirmed)",
          dataset_id: dataset_in_pool.dataset_id,
          confirmed: Snapshot.confirmed(:confirm_create)
      )

      sip = ::SnapshotInPool.create(
          snapshot: s,
          dataset_in_pool: dataset_in_pool,
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
