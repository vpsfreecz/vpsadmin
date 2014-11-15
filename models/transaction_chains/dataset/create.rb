module TransactionChains
  class Dataset::Create < ::TransactionChain
    label 'Create dataset'

    def link_chain(dataset_in_pool, path, mountpoint = nil)
      lock(dataset_in_pool)

      parent = dataset_in_pool.dataset

      path.each do |part|
        part.parent ||= parent
        part.save!

        parent = part

        dip = ::DatasetInPool.create(
            dataset: part,
            pool: dataset_in_pool.pool,
            mountpoint: mountpoint,
            confirmed: ::DatasetInPool.confirmed(:confirm_create)
        )

        lock(dip)

        append(Transactions::Storage::CreateDataset, args: dip) do
          create(part)
          create(dip)
        end

        if mountpoint
          use_chain(TransactionChains::Dataset::Set, dip, {mountpoint: mountpoint})
        end
      end

      parent
    end
  end
end
