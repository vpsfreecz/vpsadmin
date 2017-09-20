module TransactionChains
  class DatasetTree::Destroy < ::TransactionChain
    label 'Destroy dataset tree'

    def link_chain(tree)
      lock(tree)

      ::SnapshotInPoolInBranch.joins(:snapshot_in_pool, :branch).where(
            branches: {dataset_tree_id: tree.id}
      ).where.not(
            confirmed: ::SnapshotInPoolInBranch.confirmed(:confirm_destroy)
      ).order('snapshot_in_pools.reference_count, snapshot_in_pools.id').each do |sipb|
        use_chain(SnapshotInPool::Destroy, args: sipb)
      end

      tree.branches.where.not(
          confirmed: ::Branch.confirmed(:confirm_destroy)
      ).each do |branch|
        use_chain(Branch::Destroy, args: branch)
      end

      # Fetch +tree+ again - check if it was marked for destroyal
      tree_check = ::DatasetTree.find(tree.id)

      if tree_check.confirmed != :confirm_destroy
        tree_check.update!(confirmed: ::DatasetTree.confirmed(:confirm_destroy))

        append(Transactions::Storage::DestroyTree, args: tree) do
          destroy(tree)
        end
      end
    end
  end
end
