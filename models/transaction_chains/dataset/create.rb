module TransactionChains
  class Dataset::Create < ::TransactionChain
    label 'Create dataset'

    def link_chain(dataset_in_pool, path, opts = [])
      lock(dataset_in_pool)

      ret = []
      parent = dataset_in_pool.dataset

      i = 0

      path.each do |part|
        if part.new_record?
          part.parent ||= parent
          part.save!

        else
          part.expiration = nil
          part.save!
        end

        parent = part

        dip = ::DatasetInPool.create!(
            dataset: part,
            pool: dataset_in_pool.pool,
            mountpoint: opts[i] && opts[i][:mountpoint],
            confirmed: ::DatasetInPool.confirmed(:confirm_create)
        )
        ret << dip

        lock(dip)

        append(Transactions::Storage::CreateDataset, args: [dip, opts[i]]) do
          create(part)
          create(dip)
        end

        dip.call_class_hooks_for(:create, self, args: [dip])

        i += 1
      end

      ret
    end
  end
end
