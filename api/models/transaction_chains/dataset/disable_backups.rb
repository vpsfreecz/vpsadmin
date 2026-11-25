module TransactionChains
  class Dataset::DisableBackups < ::TransactionChain
    label 'Disable backups'

    def link_chain(dataset, recursive: false, backup_first: true)
      scope = VpsAdmin::API::Operations::Dataset::DisableBackups.new.prepare(
        dataset, chain: self, recursive:, backup_first:
      )
      concerns(:affect, *scope.concerns)
      preserve_snapshots(scope) if backup_first

      # This is the irreversible boundary for the entire recursive operation.
      # Even helper NoOps must not roll back successful transfers after deletion.
      scope.sources.each do |source|
        append_t(Transactions::Utils::NoOp, args: source.pool.node_id, reversible: :not_reversible) do |confirmation|
          source.dataset_in_pool_plans.each do |plan|
            definition = VpsAdmin::API::DatasetPlans.plans.fetch(plan.environment_dataset_plan.dataset_plan.name.to_sym)
            definition.unregister(source, confirmation:, keep_shared_group: true)
          end
        end
        use_chain(DatasetInPool::DetachBackupHeads, args: source, reversible: :not_reversible)
      end
      scope.snapshots.each do |snapshot|
        use_chain(SnapshotInPool::Destroy, args: snapshot, reversible: :not_reversible)
      end
    end

    protected

    def preserve_snapshots(scope)
      new_entries = []
      scope.sources.each do |source|
        ids = scope.source_snapshots(source).map(&:snapshot_id)
        next if ids.empty?

        targets = scope.targets(source)
        if targets.empty?
          raise VpsAdmin::API::Operations::Dataset::DisableBackups::Rejected,
                "source #{source.id} has snapshots but no open backup destination"
        end
        targets.each do |target|
          existing = scope.confirmed_entries(target).distinct.pluck('snapshot_in_pools.snapshot_id')
          next if (ids - existing).empty?

          use_chain(Dataset::Transfer, args: [source, target], kwargs: { send_reservation: true })
          entries = planned_entries(target, ids)
          uncovered = ids - existing - entries.map { |entry| entry.snapshot_in_pool.snapshot_id }
          unless uncovered.empty?
            raise VpsAdmin::API::Operations::Dataset::DisableBackups::Rejected,
                  "ordinary transfer cannot preserve snapshot #{uncovered.first} on backup #{target.id}"
          end
          new_entries.concat(entries.map { |entry| [target, entry] })
        end
      end
      append_missing_checks(new_entries)
    end

    def planned_entries(target, ids)
      creates = ::TransactionConfirmation.joins(:parent_transaction).where(
        transactions: { transaction_chain_id: current_chain.id }, confirm_type: :create_type
      ).to_a
      created_ids = creates.group_by(&:class_name).transform_values { |rows| rows.map { |row| row.row_pks.fetch('id') } }
      entry_ids = creates.select do |row|
        row.class_name == 'SnapshotInPoolInBranch' &&
          [Transactions::Storage::RecvCheck.t_type, Transactions::Storage::LocalSend.t_type].include?(row.parent_transaction.handle)
      end.map { |row| row.row_pks.fetch('id') }

      ::SnapshotInPoolInBranch.joins(:snapshot_in_pool, branch: :dataset_tree).where(
        id: entry_ids,
        snapshot_in_pools: { dataset_in_pool_id: target.id, snapshot_id: ids },
        dataset_trees: { dataset_in_pool_id: target.id }
      ).select do |entry|
        [entry, entry.snapshot_in_pool, entry.branch, entry.branch.dataset_tree].all? do |object|
          object.confirmed? ||
            (object.confirmed == :confirm_create && created_ids.fetch(object.class.name, []).include?(object.id))
        end
      end
    end

    def append_missing_checks(entries)
      checked = ::Transaction.where(transaction_chain_id: current_chain.id, handle: Transactions::Storage::RecvCheck.t_type).map do |tx|
        params = JSON.parse(tx.input).fetch('input')
        [tx.node_id, params['dst_pool_fs'], params['dataset_name'], params['tree'], params['branch'], params.dig('snapshot', 'id')]
      end
      entries.each do |target, entry|
        branch = entry.branch
        key = [target.pool.node_id, target.pool.filesystem, target.dataset.full_name,
               branch.dataset_tree.full_name, branch.full_name, entry.snapshot_in_pool.snapshot_id]
        next if checked.include?(key)

        append(Transactions::Storage::RecvCheck, args: [target, [entry.snapshot_in_pool], branch])
        checked << key
      end
    end
  end
end
