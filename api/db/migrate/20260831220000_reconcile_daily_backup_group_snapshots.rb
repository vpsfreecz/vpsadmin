class ReconcileDailyBackupGroupSnapshots < ActiveRecord::Migration[8.1]
  DAILY_BACKUP = 'daily_backup'.freeze
  GROUP_SNAPSHOT_ACTION = 4
  GROUP_SNAPSHOT_SCHEDULE = {
    minute: '00',
    hour: '01',
    day_of_month: '*',
    month: '*',
    day_of_week: '*'
  }.freeze

  class DatasetAction < ActiveRecord::Base
    self.table_name = 'dataset_actions'
  end

  class GroupSnapshot < ActiveRecord::Base
    self.table_name = 'group_snapshots'
  end

  class RepeatableTask < ActiveRecord::Base
    self.table_name = 'repeatable_tasks'
  end

  def up
    plan_id = connection.select_value(<<~SQL.squish)
      SELECT id
      FROM dataset_plans
      WHERE name = #{connection.quote(DAILY_BACKUP)}
      LIMIT 1
    SQL
    return unless plan_id

    plan_id = plan_id.to_i

    transaction do
      reset_models
      expected = expected_memberships(plan_id)
      remove_unexpected_memberships(plan_id, expected)

      actions = group_snapshot_actions(plan_id).to_a
      canonical_actions = find_canonical_actions(actions, expected)
      validate_tasks!(canonical_actions.values.compact)

      expected.map { |row| row.fetch('pool_id') }.uniq.each do |pool_id|
        canonical_actions[pool_id] ||= create_group_snapshot_action(plan_id, pool_id)
        ensure_task!(canonical_actions.fetch(pool_id))
      end

      expected.each do |row|
        reconcile_membership(
          plan_id,
          row.fetch('dataset_in_pool_id'),
          canonical_actions.fetch(row.fetch('pool_id'))
        )
      end

      remove_orphaned_actions(plan_id)
      validate_reconciliation!(plan_id, expected)
    end
  end

  # Restoring inconsistent group-snapshot scheduling is not a valid rollback.
  def down; end

  protected

  def reset_models
    [DatasetAction, GroupSnapshot, RepeatableTask].each(&:reset_column_information)
  end

  def expected_memberships(plan_id)
    rows = connection.select_all(<<~SQL.squish)
      SELECT DISTINCT
             dataset_in_pools.id AS dataset_in_pool_id,
             dataset_in_pools.pool_id AS pool_id
      FROM dataset_in_pool_plans
      INNER JOIN environment_dataset_plans
        ON environment_dataset_plans.id = dataset_in_pool_plans.environment_dataset_plan_id
      INNER JOIN dataset_in_pools
        ON dataset_in_pools.id = dataset_in_pool_plans.dataset_in_pool_id
      WHERE environment_dataset_plans.dataset_plan_id = #{connection.quote(plan_id)}
      ORDER BY dataset_in_pools.pool_id, dataset_in_pools.id
      FOR UPDATE
    SQL

    rows.map do |row|
      {
        'dataset_in_pool_id' => row.fetch('dataset_in_pool_id').to_i,
        'pool_id' => row.fetch('pool_id').to_i
      }
    end
  end

  def group_snapshot_actions(plan_id)
    DatasetAction
      .where(dataset_plan_id: plan_id, action: GROUP_SNAPSHOT_ACTION)
      .order(:id)
      .lock
  end

  def group_snapshots_for_plan(plan_id)
    GroupSnapshot
      .joins(<<~SQL.squish)
        INNER JOIN dataset_actions
          ON dataset_actions.id = group_snapshots.dataset_action_id
      SQL
      .where(
        dataset_actions: {
          dataset_plan_id: plan_id,
          action: GROUP_SNAPSHOT_ACTION
        }
      )
  end

  def remove_unexpected_memberships(plan_id, expected)
    expected_ids = expected.map { |row| row.fetch('dataset_in_pool_id') }
    groups = group_snapshots_for_plan(plan_id).lock
    groups = groups.where.not(dataset_in_pool_id: expected_ids) unless expected_ids.empty?
    groups.delete_all
  end

  def find_canonical_actions(actions, expected)
    expected_pool_ids = expected.map { |row| row.fetch('pool_id') }.uniq

    expected_pool_ids.to_h do |pool_id|
      candidates = actions.select { |action| action.pool_id == pool_id }

      if candidates.length > 1
        raise ActiveRecord::MigrationError,
              "multiple daily-backup group snapshot actions for pool #{pool_id}: " \
              "#{candidates.map(&:id).join(', ')}"
      end

      [pool_id, candidates.first]
    end
  end

  def validate_tasks!(actions)
    actions.each do |action|
      tasks = tasks_for(action).limit(2).to_a
      next if tasks.length < 2

      raise ActiveRecord::MigrationError,
            "multiple repeatable tasks for daily-backup group snapshot action #{action.id}: " \
            "#{tasks.map(&:id).join(', ')}"
    end
  end

  def create_group_snapshot_action(plan_id, pool_id)
    DatasetAction.create!(
      dataset_plan_id: plan_id,
      pool_id: pool_id,
      action: GROUP_SNAPSHOT_ACTION
    )
  end

  def ensure_task!(action)
    task = tasks_for(action).first

    if task
      task.update!(GROUP_SNAPSHOT_SCHEDULE)
    else
      RepeatableTask.create!(
        class_name: 'DatasetAction',
        table_name: 'dataset_actions',
        row_id: action.id,
        **GROUP_SNAPSHOT_SCHEDULE
      )
    end
  end

  def tasks_for(action)
    RepeatableTask.where(
      class_name: 'DatasetAction',
      table_name: 'dataset_actions',
      row_id: action.id
    ).order(:id).lock
  end

  def reconcile_membership(plan_id, dataset_in_pool_id, canonical_action)
    groups = group_snapshots_for_plan(plan_id)
             .where(
               dataset_in_pool_id: dataset_in_pool_id
             )
             .order('group_snapshots.id')
             .lock
             .to_a

    keeper = groups.find { |group| group.dataset_action_id == canonical_action.id } || groups.first

    if keeper
      keeper.update!(dataset_action_id: canonical_action.id)
    else
      keeper = GroupSnapshot.create!(
        dataset_in_pool_id: dataset_in_pool_id,
        dataset_action_id: canonical_action.id
      )
    end

    groups.each do |group|
      group.destroy! unless group.id == keeper.id
    end
  end

  def remove_orphaned_actions(plan_id)
    group_snapshot_actions(plan_id).each do |action|
      next if GroupSnapshot.exists?(dataset_action_id: action.id)

      tasks_for(action).delete_all
      action.destroy!
    end
  end

  def validate_reconciliation!(plan_id, expected)
    expected_ids = expected.map { |row| row.fetch('dataset_in_pool_id') }
    actual_ids = group_snapshots_for_plan(plan_id).pluck(:dataset_in_pool_id)
    unexpected = actual_ids - expected_ids

    unless unexpected.empty?
      raise ActiveRecord::MigrationError,
            'unexpected daily-backup group snapshot memberships for dataset_in_pool IDs: ' \
            "#{unexpected.join(', ')}"
    end

    broken = expected.filter_map do |row|
      dataset_in_pool_id = row.fetch('dataset_in_pool_id')
      pool_id = row.fetch('pool_id')
      groups = group_snapshots_for_plan(plan_id)
               .where(
                 dataset_in_pool_id: dataset_in_pool_id
               )

      next if groups.one? && groups.where(dataset_actions: { pool_id: pool_id }).exists?

      dataset_in_pool_id
    end

    return if broken.empty?

    raise ActiveRecord::MigrationError,
          'daily-backup group snapshot reconciliation failed for dataset_in_pool IDs: ' \
          "#{broken.join(', ')}"
  end
end
