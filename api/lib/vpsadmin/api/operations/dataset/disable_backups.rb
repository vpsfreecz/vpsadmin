require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Dataset::DisableBackups < Operations::Base
    class Rejected < StandardError; end

    attr_reader :root, :recursive, :sources, :backups, :snapshots

    def run(root, recursive: false, backup_first: true)
      TransactionChains::Dataset::DisableBackups.fire(root, recursive:, backup_first:)
    end

    def prepare(root, chain:, recursive:, backup_first:)
      @root = root
      @recursive = recursive
      @chain = chain
      acquire_scope!
      preflight!(backup_first:)
      self
    end

    def targets(source)
      backups.select { |b| b.dataset_id == source.dataset_id && b.pool.is_open == 1 }
    end

    def source_snapshots(source)
      snapshots.select { |s| s.dataset_in_pool_id == source.id }
    end

    def concerns
      (sources.map(&:dataset) + sources + backups.select { |b| b.pool.is_open == 1 } +
        snapshots + snapshots.map(&:snapshot)).map { |obj| [obj.class.name, obj.id] }.uniq
    end

    def confirmed_entries(target)
      ::SnapshotInPoolInBranch.joins(:branch, :snapshot_in_pool)
                              .joins(branch: :dataset_tree)
                              .lock
                              .where(
                                snapshot_in_pool_in_branches: { confirmed: 1 },
                                snapshot_in_pools: { dataset_in_pool_id: target.id, confirmed: 1 },
                                branches: { confirmed: 1 },
                                dataset_trees: { dataset_in_pool_id: target.id, confirmed: 1 }
                              )
    end

    protected

    def dataset_scope(locked: true)
      root.reload(lock: locked ? 'FOR UPDATE NOWAIT' : false)
      query = (recursive ? root.subtree : ::Dataset.where(id: root.id)).order(:id)
      query = query.lock('FOR UPDATE NOWAIT') if locked
      query.to_a
    end

    def source_scope(datasets, locked: true)
      datasets.map do |dataset|
        query = dataset.dataset_in_pools.joins(:pool).where(pools: { role: %w[primary hypervisor] })
        query = query.lock('FOR UPDATE NOWAIT') if locked
        copies = query.to_a
        raise Rejected, "dataset #{dataset.id} needs exactly one current source" unless copies.one?
        raise Rejected, "dataset #{dataset.id} has another owner" unless dataset.user_id == root.user_id

        copies.first
      end
    end

    def acquire_scope!
      @sources = source_scope(dataset_scope(locked: false), locked: false)
      # Stable order: VPSes, source copies, all backup copies, source snapshots.
      @vpses = sources.select { |s| s.pool.role == 'hypervisor' }.map do |source|
        ::Vps.find_by!(dataset_in_pool: source.dataset.root.primary_dataset_in_pool!)
      end.uniq(&:id).sort_by(&:id)
      @vpses.each { |vps| acquire(vps) }
      sources.sort_by(&:id).each { |source| acquire(source) }
      fresh_sources = source_scope(dataset_scope)
      unless fresh_sources.map { |s| [s.id, s.dataset_id, s.pool_id] } == sources.map { |s| [s.id, s.dataset_id, s.pool_id] }
        raise Rejected, 'dataset scope changed while locking; retry'
      end

      @sources = fresh_sources
      @backups = ::DatasetInPool.joins(:pool).where(dataset_id: sources.map(&:dataset_id), pools: { role: 'backup' })
                                .order(:id).lock.to_a
      backups.each { |backup| acquire(backup) }
      @snapshots = ::SnapshotInPool.where(dataset_in_pool: sources).order(:snapshot_id, :id).lock.to_a
      snapshots.each { |snapshot| acquire(snapshot) }
      # Locking reads see current committed state even if the caller already
      # established a REPEATABLE-READ snapshot before acquiring resource locks.
      (sources + backups).each do |copy|
        copy.reload(lock: true)
        copy.dataset.reload(lock: true)
        copy.pool.reload(lock: true)
        copy.pool.node.reload(lock: true)
      end
      sources.each { |source| source.dataset.user.reload(lock: true) }
      snapshots.each { |snapshot| snapshot.snapshot.reload(lock: true) }
      @vpses.each { |vps| vps.reload(lock: true) }
    end

    def acquire(object)
      @chain.lock(object)
    end

    def preflight!(backup_first:)
      nonempty_datasets = sources.select { |source| source_snapshots(source).any? }.map(&:dataset_id)
      (sources + backups).each do |copy|
        confirmed!(copy)
        next unless copy.pool.role != 'backup' ||
                    (backup_first && nonempty_datasets.include?(copy.dataset_id) && copy.pool.is_open == 1)

        check_available!(copy.pool)
        check_available!(copy.pool.node)
      end
      (sources.map(&:dataset) + sources.map { |s| s.dataset.user } + @vpses).each do |object|
        confirmed!(object) if object.respond_to?(:confirmed?)
        check_available!(object)
        raise Rejected, "#{object.class} #{object.id} is not active" unless object.object_state == 'active'
      end
      snapshots.each do |snapshot|
        confirmed!(snapshot)
        confirmed!(snapshot.snapshot)
        unless snapshot.snapshot.dataset_id == snapshot.dataset_in_pool.dataset_id
          raise Rejected, "source snapshot #{snapshot.id} has an inconsistent dataset"
        end
        if snapshot.reference_count > 0 || snapshot.mount_id || snapshot.mounts.lock.exists? ||
           ::SnapshotInPoolClone.where(snapshot_in_pool: snapshot).lock.exists?
          raise Rejected, "source snapshot #{snapshot.id} is in use"
        end
      end
      backups.each do |backup|
        if backup.dataset_trees.where(head: true).lock.to_a.size > 1 ||
           backup.dataset_trees.lock.any? { |tree| tree.branches.where(head: true).lock.to_a.size > 1 }
          raise Rejected, "backup #{backup.id} has inconsistent heads"
        end

        [backup.snapshot_in_pools, backup.dataset_trees,
         ::Branch.joins(:dataset_tree).where(dataset_trees: { dataset_in_pool_id: backup.id }),
         ::SnapshotInPoolInBranch.joins(:snapshot_in_pool).where(snapshot_in_pools: { dataset_in_pool_id: backup.id })].each do |rows|
          raise Rejected, "backup #{backup.id} has pending storage changes" if rows.where.not(confirmed: 1).lock.exists?
        end
      end
      sources.each { |source| validate_automation!(source) }
    end

    def confirmed!(object)
      raise Rejected, "#{object.class} #{object.id} has pending changes" unless object.confirmed?
    end

    def check_available!(object)
      if object.respond_to?(:maintenance_lock) && object.maintenance_lock != ::MaintenanceLock.maintain_lock(:no)
        raise Rejected, "#{object.class} #{object.id} is under maintenance"
      end
      if object.is_a?(::Pool) && %w[suspended faulted error].include?(object.state)
        raise Rejected, "pool #{object.id} is unavailable"
      end
      return unless object.is_a?(::Node) && !object.active

      raise Rejected, "node #{object.id} is unavailable"
    end

    def validate_automation!(source)
      plans = source.dataset_in_pool_plans.lock.to_a
      plans.each do |plan|
        environment_plan = ::EnvironmentDatasetPlan.lock.find(plan.environment_dataset_plan_id)
        name = environment_plan.dataset_plan.name.to_sym
        raise Rejected, "unsupported dataset plan #{name}" unless DatasetPlans.plans.has_key?(name)
        unless environment_plan.environment_id == source.pool.node.location.environment_id
          raise Rejected, "source #{source.id} has a plan from another environment"
        end
      end
      actions = ::DatasetAction.where(src_dataset_in_pool: source).lock.to_a
      unless actions.all? { |action| action.action == 'backup' && plans.any? { |plan| plan.id == action.dataset_in_pool_plan_id } }
        raise Rejected, "source #{source.id} has unsupported non-plan automation"
      end
      if ::DatasetAction.where(dst_dataset_in_pool: source).lock.exists?
        raise Rejected, "source #{source.id} has unsupported incoming automation"
      end

      plan_ids = plans.map { |p| p.environment_dataset_plan.dataset_plan_id }
      members = source.group_snapshots.lock.to_a
      seen = []
      members.each do |member|
        action = ::DatasetAction.lock.find_by(id: member.dataset_action_id)
        unless action && action.action == 'group_snapshot' && action.pool_id == source.pool_id &&
               plan_ids.include?(action.dataset_plan_id) && !seen.include?(action.dataset_plan_id)
          raise Rejected, "source #{source.id} has unsupported group automation"
        end

        seen << action.dataset_plan_id
      end
    end
  end
end
