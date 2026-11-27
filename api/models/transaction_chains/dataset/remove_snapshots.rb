module TransactionChains
  class Dataset::RemoveSnapshots < ::TransactionChain
    label 'Remove snapshots'

    def link_chain(dataset, manifest_digest:, recursive: false, disable_plans: true)
      scope = VpsAdmin::API::Operations::Dataset::RemoveSnapshots.new.prepare(dataset, chain: self, recursive:, disable_plans:)
      scope.verify_review!(manifest_digest)
      concerns(:affect, *scope.concerns)

      # Every helper shares the irreversible suffix, even for empty inventories.
      scope.sources.each do |source|
        append_t(Transactions::Utils::NoOp, args: source.pool.node_id, reversible: :not_reversible) do |confirmation|
          next unless disable_plans

          source.dataset_in_pool_plans.each do |plan|
            definition = VpsAdmin::API::DatasetPlans.plans.fetch(plan.environment_dataset_plan.dataset_plan.name.to_sym)
            definition.unregister(source, confirmation:, keep_shared_group: true)
          end
        end
      end
      scope.branch_order.each do |branch|
        scope.entries.select { |entry| entry.branch_id == branch.id }.sort_by(&:id).each do |entry|
          use_chain(SnapshotInPool::Destroy, args: entry, reversible: :not_reversible)
        end
        unless branch.reload.confirmed == :confirm_destroy
          use_chain(Branch::Destroy, args: branch, reversible: :not_reversible)
        end
      end
      scope.trees.each do |tree|
        next if tree.reload.confirmed == :confirm_destroy

        tree.update!(confirmed: ::DatasetTree.confirmed(:confirm_destroy))
        append_t(Transactions::Storage::DestroyTree, args: tree, reversible: :not_reversible) { |tx| tx.destroy(tree) }
      end
      scope.snapshots.each do |sip|
        use_chain(SnapshotInPool::Destroy, args: sip, reversible: :not_reversible)
      end
    end
  end
end
