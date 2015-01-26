module TransactionChains
  class DatasetTree::Destroy < ::TransactionChain
    label 'Destroy dataset tree'

    def link_chain(tree)
      lock(tree)
      tree.update!(confirmed: ::DatasetTree.confirmed(:confirm_destroy))

      tree.dataset_in_pool.snapshot_in_pools.order('reference_count, id').each do |sip|
        use_chain(SnapshotInPool::Destroy, args: sip)
      end

      tree.branches.each do |branch|
        use_chain(Branch::Destroy, args: branch)
      end

      append(Transactions::Storage::DestroyTree, args: tree) do
        destroy(tree)
      end
    end
  end
end
