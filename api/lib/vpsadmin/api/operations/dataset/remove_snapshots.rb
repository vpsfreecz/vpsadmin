require 'vpsadmin/api/operations/dataset/disable_backups'
require 'vpsadmin/api/operations/dataset/snapshot_removal_manifest'
require 'vpsadmin/api/operations/dataset/snapshot_removal_order'

module VpsAdmin::API
  class Operations::Dataset::RemoveSnapshots < Operations::Dataset::DisableBackups
    class StalePreview < Rejected; end

    attr_reader :disable_plans, :copies, :all_snapshots, :trees, :branches, :entries, :branch_order, :plans

    def run(root, manifest_digest:, recursive: false, disable_plans: true)
      TransactionChains::Dataset::RemoveSnapshots.fire(root, recursive:, disable_plans:, manifest_digest:)
    end

    def preview(root, recursive: false, disable_plans: true)
      # No preview rows or resource locks are created. Use a consistent snapshot
      # even though the product normally uses READ-COMMITTED.
      ::Dataset.connection_pool.with_connection do |connection|
        connection.execute('SET TRANSACTION READ ONLY')
        ::Dataset.transaction(isolation: :repeatable_read) do
          prepare(root, chain: nil, recursive:, disable_plans:).inventory
        end
      end
    end

    def prepare(root, chain:, recursive:, disable_plans:)
      @disable_plans = disable_plans
      super(root, chain:, recursive:, backup_first: false)
      self
    end

    def inventory
      Operations::Dataset::SnapshotRemovalManifest.new(self).export
    end

    def verify_review!(digest)
      return if digest.is_a?(String) && digest.match?(/\Av1:[0-9a-f]{64}\z/) && digest == inventory.fetch(:manifest_digest)

      raise StalePreview, 'snapshot removal preview changed'
    end

    def concerns
      (sources.map(&:dataset) + copies + all_snapshots + all_snapshots.map(&:snapshot)).map { |obj| [obj.class.name, obj.id] }.uniq
    end

    protected

    def acquire(object)
      @chain&.lock(object)
    end

    def dataset_scope
      root.reload(lock: !@chain.nil?)
      @datasets = current(recursive ? root.subtree : ::Dataset.where(id: root.id)).order(:id).to_a
    end

    def source_scope(datasets)
      datasets.map do |dataset|
        rows = current(dataset.dataset_in_pools.joins(:pool).where(pools: { role: %w[primary hypervisor] })).to_a
        raise Rejected, "dataset #{dataset.id} needs exactly one current source" unless rows.one?
        raise Rejected, "dataset #{dataset.id} has another owner" unless dataset.user_id == root.user_id

        rows.first.tap { |copy| copy.dataset = dataset }
      end
    end

    def current(query)
      @chain ? query.lock : query
    end

    def acquire_scope!
      super
      @copies = current(::DatasetInPool.where(dataset_id: sources.map(&:dataset_id))).order(:id).to_a
      unless copies.map(&:id) == (sources + backups).map(&:id).sort
        raise Rejected, 'dataset copies changed while locking; retry'
      end

      datasets = @datasets.index_by(&:id)
      pools = current(::Pool.where(id: copies.map(&:pool_id))).order(:id).index_by(&:id)
      nodes = current(::Node.where(id: pools.values.map(&:node_id))).order(:id).index_by(&:id)
      copies.each do |copy|
        copy.dataset = datasets.fetch(copy.dataset_id)
        copy.dataset.user = current(::User.where(id: copy.dataset.user_id)).take!
        copy.pool = pools.fetch(copy.pool_id)
        copy.pool.node = nodes.fetch(copy.pool.node_id)
      end
      @backups, @sources = copies.partition { |copy| copy.pool.role == 'backup' }
      @vpses.each { |vps| vps.reload(lock: !@chain.nil?) }
      load_history!
      key = history_key
      (all_snapshots + all_snapshots.map(&:snapshot).uniq(&:id) + trees + branches + entries).each { |row| acquire(row) }
      load_history!
      raise Rejected, 'snapshot scope changed while locking; retry' unless history_key == key

      @snapshots = all_snapshots.select { |sip| sources.any? { |source| source.id == sip.dataset_in_pool_id } }
    end

    def load_history!
      @all_snapshots = current(::SnapshotInPool.where(dataset_in_pool: copies)).order(:id).to_a
      @trees = current(::DatasetTree.where(dataset_in_pool: copies)).order(:id).to_a
      @branches = current(::Branch.where(dataset_tree: trees)).order(:id).to_a
      # Include both ends so a malformed foreign membership cannot disappear
      # from the inventory merely because one of its ownership links is wrong.
      @entries = current(::SnapshotInPoolInBranch.where(snapshot_in_pool: all_snapshots)
                         .or(::SnapshotInPoolInBranch.where(branch: branches))).order(:id).to_a
      @plans = current(::DatasetInPoolPlan.where(dataset_in_pool: sources)).order(:id).to_a
      # A current locking read of SIP does not make a later ordinary association
      # lookup current under REPEATABLE-READ. Load every authoritative endpoint
      # the same way, including newly committed snapshots absent from an old view.
      snapshots = current(::Snapshot.where(id: all_snapshots.map(&:snapshot_id))).order(:id).index_by(&:id)
      copy_by_id = copies.index_by(&:id)
      tree_by_id = trees.index_by(&:id)
      branch_by_id = branches.index_by(&:id)
      sip_by_id = all_snapshots.index_by(&:id)
      entry_by_id = entries.index_by(&:id)
      all_snapshots.each do |sip|
        raise Rejected, "snapshot copy #{sip.id} has no snapshot" unless snapshots[sip.snapshot_id]

        sip.snapshot = snapshots.fetch(sip.snapshot_id)
        sip.dataset_in_pool = copy_by_id.fetch(sip.dataset_in_pool_id)
      end
      trees.each { |tree| tree.dataset_in_pool = copy_by_id.fetch(tree.dataset_in_pool_id) }
      branches.each { |branch| branch.dataset_tree = tree_by_id.fetch(branch.dataset_tree_id) }
      entries.each do |entry|
        entry.snapshot_in_pool = sip_by_id.fetch(entry.snapshot_in_pool_id) if sip_by_id.has_key?(entry.snapshot_in_pool_id)
        entry.branch = branch_by_id.fetch(entry.branch_id) if branch_by_id.has_key?(entry.branch_id)
        if entry_by_id.has_key?(entry.snapshot_in_pool_in_branch_id)
          entry.snapshot_in_pool_in_branch = entry_by_id.fetch(entry.snapshot_in_pool_in_branch_id)
        end
      end
    end

    def history_key
      [all_snapshots.map { |row| [row.id, row.dataset_in_pool_id, row.snapshot_id] },
       trees.map { |row| [row.id, row.dataset_in_pool_id] }, branches.map { |row| [row.id, row.dataset_tree_id] },
       entries.map { |row| [row.id, row.snapshot_in_pool_id, row.branch_id, row.snapshot_in_pool_in_branch_id] }]
    end

    def preflight!(backup_first:)
      super
      copies.each do |copy|
        check_available!(copy.pool)
        check_available!(copy.pool.node)
      end
      (trees + branches + entries).each { |row| confirmed!(row) }
      tree_ids = trees.map(&:id)
      backup_ids = backups.map(&:id)
      trees.each do |tree|
        raise Rejected, "tree #{tree.id} is not backup history" unless backup_ids.include?(tree.dataset_in_pool_id)
      end
      branches.each do |branch|
        raise Rejected, "branch #{branch.id} has a foreign tree" unless tree_ids.include?(branch.dataset_tree_id)
      end
      all_snapshots.each { |sip| validate_snapshot!(sip) }
      entries.each { |entry| validate_entry!(entry) }
      validate_backup_automation!
      if current(::Snapshot.where(dataset_id: sources.map(&:dataset_id)).where.not(id: all_snapshots.map(&:snapshot_id))).exists?
        raise Rejected, 'dataset has snapshot records without storage copies'
      end

      @branch_order = Operations::Dataset::SnapshotRemovalOrder.new(branches, entries, all_snapshots).order
    end

    def validate_automation!(source)
      source_plans = plans.select { |plan| plan.dataset_in_pool_id == source.id }
      source_plans.each do |plan|
        environment_plan = current(::EnvironmentDatasetPlan.where(id: plan.environment_dataset_plan_id)).take!
        definition = current(::DatasetPlan.where(id: environment_plan.dataset_plan_id)).take!
        unless DatasetPlans.plans.has_key?(definition.name.to_sym) &&
               environment_plan.environment_id == source.pool.node.location.environment_id
          raise Rejected, "source #{source.id} has an unsupported plan"
        end

        environment_plan.dataset_plan = definition
        plan.environment_dataset_plan = environment_plan
      end
      actions = current(::DatasetAction.where(src_dataset_in_pool: source)).to_a
      destinations = backups.select { |backup| backup.dataset_id == source.dataset_id }.map(&:id)
      unless actions.all? do |action|
        action.action == 'backup' && destinations.include?(action.dst_dataset_in_pool_id) &&
        source_plans.any? { |plan| plan.id == action.dataset_in_pool_plan_id }
      end
        raise Rejected, "source #{source.id} has unsupported non-plan automation"
      end
      if current(::DatasetAction.where(dst_dataset_in_pool: source)).exists?
        raise Rejected, "source #{source.id} has unsupported incoming automation"
      end

      plan_ids = source_plans.map { |plan| plan.environment_dataset_plan.dataset_plan_id }
      seen = []
      current(::GroupSnapshot.where(dataset_in_pool: source)).each do |member|
        action = current(::DatasetAction.where(id: member.dataset_action_id)).take
        unless action && action.action == 'group_snapshot' && action.pool_id == source.pool_id &&
               plan_ids.include?(action.dataset_plan_id) && !seen.include?(action.dataset_plan_id)
          raise Rejected, "source #{source.id} has unsupported group automation"
        end

        seen << action.dataset_plan_id
      end
    end

    def validate_backup_automation!
      if current(::DatasetInPoolPlan.where(dataset_in_pool: backups)).exists? ||
         current(::GroupSnapshot.where(dataset_in_pool: backups)).exists? ||
         current(::DatasetAction.where(src_dataset_in_pool: backups)).exists?
        raise Rejected, 'backup history has unsupported automation'
      end

      current(::DatasetAction.where(dst_dataset_in_pool: backups)).each do |action|
        source = sources.find { |copy| copy.id == action.src_dataset_in_pool_id }
        target = backups.find { |copy| copy.id == action.dst_dataset_in_pool_id }
        unless action.action == 'backup' && source && target && source.dataset_id == target.dataset_id &&
               plans.any? { |plan| plan.id == action.dataset_in_pool_plan_id && plan.dataset_in_pool_id == source.id }
          raise Rejected, 'backup history has foreign incoming automation'
        end
      end
    end

    def validate_snapshot!(sip)
      confirmed!(sip)
      confirmed!(sip.snapshot)
      unless sip.snapshot.dataset_id == sip.dataset_in_pool.dataset_id
        raise Rejected, "snapshot copy #{sip.id} has a foreign dataset"
      end
      if sip.mount_id || sip.mounts.exists? || ::SnapshotInPoolClone.where(snapshot_in_pool: sip).exists?
        raise Rejected, "snapshot copy #{sip.id} is in use"
      end

      memberships = entries.select { |entry| entry.snapshot_in_pool_id == sip.id }
      return unless sip.dataset_in_pool.pool.role == 'backup' && memberships.empty?

      raise Rejected, "backup snapshot copy #{sip.id} has no branch membership"
    end

    def validate_entry!(entry)
      sip = all_snapshots.find { |row| row.id == entry.snapshot_in_pool_id }
      branch = branches.find { |row| row.id == entry.branch_id }
      unless sip && branch && sip.dataset_in_pool.pool.role == 'backup' &&
             branch.dataset_tree.dataset_in_pool_id == sip.dataset_in_pool_id
        raise Rejected, "snapshot membership #{entry.id} has foreign ownership"
      end
    end
  end
end
