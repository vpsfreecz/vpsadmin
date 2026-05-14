require_relative 'confirmable'
require_relative 'lockable'

class SnapshotInPoolInBranch < ApplicationRecord
  belongs_to :snapshot_in_pool
  belongs_to :branch
  belongs_to :snapshot_in_pool_in_branch

  include Confirmable
  include Lockable

  class << self
    def live
      joins(snapshot_in_pool: { dataset_in_pool: :pool })
        .joins(branch: [:dataset_tree])
        .where.not(snapshot_in_pool_in_branches: { confirmed: confirmed(:confirm_destroy) })
        .where.not(snapshot_in_pools: { confirmed: ::SnapshotInPool.confirmed(:confirm_destroy) })
        .where.not(branches: { confirmed: ::Branch.confirmed(:confirm_destroy) })
        .where.not(dataset_trees: { confirmed: ::DatasetTree.confirmed(:confirm_destroy) })
    end

    def for_snapshot(dataset_in_pool:, snapshot:)
      scope = live.where(snapshot_in_pools: { snapshot_id: snapshot_id(snapshot) })

      if dataset_in_pool
        scope.where(dataset_trees: { dataset_in_pool_id: dataset_in_pool.id })
      else
        scope.where(pools: { role: ::Pool.roles[:backup] })
      end
    end

    def find_for_snapshot(dataset_in_pool:, snapshot:)
      prefer_head(for_snapshot(dataset_in_pool:, snapshot:)).take
    end

    def find_for_snapshot!(dataset_in_pool:, snapshot:)
      prefer_head(for_snapshot(dataset_in_pool:, snapshot:)).take!
    end

    def find_tip_for_snapshot(dataset_in_pool:, snapshot:)
      snap_id = snapshot_id(snapshot)
      scope = for_snapshot(dataset_in_pool:, snapshot:)
      newer_branch_ids = live.where(
        dataset_trees: { dataset_in_pool_id: dataset_in_pool.id }
      ).where(
        'snapshot_in_pools.snapshot_id > ?', snap_id
      ).select(:branch_id)

      prefer_head(scope.where.not(branch_id: newer_branch_ids)).take ||
        prefer_head(scope).take
    end

    def find_tip_for_snapshot!(dataset_in_pool:, snapshot:)
      find_tip_for_snapshot(dataset_in_pool:, snapshot:) || raise(
        ActiveRecord::RecordNotFound,
        'backup branch containing snapshot was not found'
      )
    end

    def find_pair_for_incremental(snapshot:, from_snapshot:, dataset_in_pool: nil)
      target_scope = live.where(
        pools: { role: ::Pool.roles[:backup] },
        snapshot_in_pools: { snapshot_id: snapshot_id(snapshot) }
      )
      base_scope = live.where(
        pools: { role: ::Pool.roles[:backup] },
        snapshot_in_pools: { snapshot_id: snapshot_id(from_snapshot) }
      )

      if dataset_in_pool
        target_scope = target_scope.where(dataset_trees: { dataset_in_pool_id: dataset_in_pool.id })
        base_scope = base_scope.where(dataset_trees: { dataset_in_pool_id: dataset_in_pool.id })
      end

      target_entry = prefer_head(target_scope.where(branch_id: base_scope.select(:branch_id))).take
      return unless target_entry

      base_entry = base_scope.where(branch_id: target_entry.branch_id).take!

      [base_entry, target_entry]
    end

    def find_pair_for_incremental!(snapshot:, from_snapshot:, dataset_in_pool: nil)
      find_pair_for_incremental(snapshot:, from_snapshot:, dataset_in_pool:) || raise(
        ActiveRecord::RecordNotFound,
        'backup branch containing both snapshots was not found'
      )
    end

    def find_head_for_snapshot(snapshot:, open_pool: false)
      scope = live.where(
        pools: { role: ::Pool.roles[:backup] },
        dataset_trees: { head: true },
        branches: { head: true },
        snapshot_in_pools: { snapshot_id: snapshot_id(snapshot) }
      )

      scope = scope.where(pools: { is_open: true }) if open_pool

      prefer_head(scope).take
    end

    def head_contains_newer_source_snapshot?(backup_dip:, source_dip:, snapshot_id:)
      source_sips = source_dip.snapshot_in_pools
      newer_source_ids = source_sips
                         .where.not(confirmed: ::SnapshotInPool.confirmed(:confirm_destroy))
                         .where('snapshot_id > ?', snapshot_id)
                         .select(:snapshot_id)

      live.where(
        dataset_trees: {
          dataset_in_pool_id: backup_dip.id,
          head: true
        },
        branches: { head: true },
        snapshot_in_pools: { snapshot_id: newer_source_ids }
      ).exists?
    end

    def prefer_head(scope)
      scope.order(
        Arel.sql('dataset_trees.head DESC'),
        Arel.sql('branches.head DESC'),
        Arel.sql('dataset_trees.`index` DESC'),
        Arel.sql('branches.`index` DESC'),
        Arel.sql('dataset_trees.id DESC'),
        Arel.sql('branches.id DESC'),
        Arel.sql('snapshot_in_pool_in_branches.id DESC')
      )
    end

    private

    def snapshot_id(snapshot)
      snapshot.respond_to?(:id) ? snapshot.id : snapshot
    end
  end
end
