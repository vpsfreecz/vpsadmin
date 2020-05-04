module TransactionChains
  class DatasetInPool::DetachBackupHeads < ::TransactionChain
    label 'Detach backups'
    allow_empty

    # @param dataset_in_pool [::DatasetInPool]
    def link_chain(dataset_in_pool)
      lock(dataset_in_pool)

      concerns(:affect, [
        dataset_in_pool.dataset.class.name,
        dataset_in_pool.dataset_id
      ])

      changes = {}

      dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where(
        pools: {role: ::Pool.roles[:backup]}
      ).each do |backup|
        lock(backup)

        backup.dataset_trees.all.each do |tree|
          changes[tree] = {head: false}

          tree.branches.where(head: true).each do |b|
            changes[b] = {head: false}
          end
        end
      end

      if changes.any?
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          changes.each { |obj, v| t.edit(obj, v) }
        end
      end
    end
  end
end
