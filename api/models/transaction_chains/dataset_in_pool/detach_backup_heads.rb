module TransactionChains
  class DatasetInPool::DetachBackupHeads < ::TransactionChain
    label 'Detach backups'
    allow_empty
    storage_effect :catalog_topology

    # @param dataset_in_pool [::DatasetInPool]
    def link_chain(dataset_in_pool)
      lock(dataset_in_pool)

      concerns(:affect, [
                 dataset_in_pool.dataset.class.name,
                 dataset_in_pool.dataset_id
               ])

      changes = {}
      affected_dips = []

      dataset_in_pool.dataset.dataset_in_pools.joins(:pool).where(
        pools: { role: ::Pool.roles[:backup] }
      ).each do |backup|
        lock(backup)
        affected_dips << backup

        backup.dataset_trees.all.each do |tree|
          changes[tree] = { head: false }

          tree.branches.where(head: true).each do |b|
            changes[b] = { head: false }
          end
        end
      end

      return unless changes.any?

      ::StorageMutationJournal.mark_catalog_topology!(affected_dips)

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        changes.each { |obj, v| t.edit(obj, v) }
      end
    end
  end
end
