# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260831220000_reconcile_daily_backup_group_snapshots')

RSpec.describe ReconcileDailyBackupGroupSnapshots do
  before do
    define_schema do
      create_table :dataset_plans do |t|
        t.string :name, null: false
      end

      create_table :environment_dataset_plans do |t|
        t.integer :dataset_plan_id, null: false
        t.integer :environment_id, null: false
        t.boolean :user_add, null: false, default: true
        t.boolean :user_remove, null: false, default: true
      end

      create_table :dataset_in_pools do |t|
        t.integer :dataset_id, null: false
        t.integer :pool_id, null: false
      end

      create_table :dataset_in_pool_plans do |t|
        t.integer :dataset_in_pool_id, null: false
        t.integer :environment_dataset_plan_id, null: false
      end

      create_table :dataset_actions do |t|
        t.integer :action, null: false
        t.integer :dataset_in_pool_plan_id
        t.integer :dataset_plan_id
        t.integer :dst_dataset_in_pool_id
        t.integer :pool_id
        t.boolean :recursive, null: false, default: false
        t.integer :snapshot_id
        t.integer :src_dataset_in_pool_id
      end

      create_table :group_snapshots do |t|
        t.integer :dataset_action_id
        t.integer :dataset_in_pool_id
      end
      add_index :group_snapshots, %i[dataset_action_id dataset_in_pool_id], unique: true

      create_table :repeatable_tasks do |t|
        t.string :class_name, null: false
        t.string :day_of_month, null: false
        t.string :day_of_week, null: false
        t.string :hour, null: false
        t.string :label
        t.string :minute, null: false
        t.string :month, null: false
        t.integer :row_id, null: false
        t.string :table_name, null: false
      end
    end
  end

  def create_plan(name = 'daily_backup')
    plan_id = insert_row(:dataset_plans, name: name)
    env_plan_id = insert_row(
      :environment_dataset_plans,
      dataset_plan_id: plan_id,
      environment_id: 17,
      user_add: true,
      user_remove: true
    )

    [plan_id, env_plan_id]
  end

  def create_dip(pool_id:, dataset_id:)
    insert_row(:dataset_in_pools, pool_id: pool_id, dataset_id: dataset_id)
  end

  def assign_plan(dip_id, env_plan_id)
    insert_row(
      :dataset_in_pool_plans,
      dataset_in_pool_id: dip_id,
      environment_dataset_plan_id: env_plan_id
    )
  end

  def create_action(plan_id:, pool_id:)
    insert_row(
      :dataset_actions,
      action: described_class::GROUP_SNAPSHOT_ACTION,
      dataset_plan_id: plan_id,
      pool_id: pool_id,
      recursive: false
    )
  end

  def create_group(action_id:, dip_id:)
    insert_row(
      :group_snapshots,
      dataset_action_id: action_id,
      dataset_in_pool_id: dip_id
    )
  end

  def create_task(action_id:, hour: '01')
    insert_row(
      :repeatable_tasks,
      class_name: 'DatasetAction',
      table_name: 'dataset_actions',
      row_id: action_id,
      minute: '00',
      hour: hour,
      day_of_month: '*',
      month: '*',
      day_of_week: '*',
      label: nil
    )
  end

  def group_rows(plan_id)
    connection.select_all(<<~SQL.squish).to_a
      SELECT group_snapshots.id,
             group_snapshots.dataset_in_pool_id,
             group_snapshots.dataset_action_id,
             dataset_actions.pool_id
      FROM group_snapshots
      INNER JOIN dataset_actions
        ON dataset_actions.id = group_snapshots.dataset_action_id
      WHERE dataset_actions.dataset_plan_id = #{connection.quote(plan_id)}
        AND dataset_actions.action = #{described_class::GROUP_SNAPSHOT_ACTION}
      ORDER BY group_snapshots.dataset_in_pool_id, group_snapshots.id
    SQL
  end

  it 'repairs mixed and missing memberships without deployment-specific IDs' do
    create_plan('unrelated-plan')
    plan_id, env_plan_id = create_plan
    first_pool = 701
    second_pool = 909
    first_dips = [41, 42, 43].map do |dataset_id|
      create_dip(pool_id: first_pool, dataset_id: dataset_id)
    end
    second_dips = [51, 52].map do |dataset_id|
      create_dip(pool_id: second_pool, dataset_id: dataset_id)
    end
    (first_dips + second_dips).each { |dip_id| assign_plan(dip_id, env_plan_id) }

    first_action = create_action(plan_id: plan_id, pool_id: first_pool)
    create_task(action_id: first_action, hour: '03')
    create_group(action_id: first_action, dip_id: first_dips.first)
    second_dips.each { |dip_id| create_group(action_id: first_action, dip_id: dip_id) }

    migrate_up!

    rows = group_rows(plan_id)
    expect(rows.map { |row| row.fetch('dataset_in_pool_id').to_i }).to match_array(first_dips + second_dips)
    expect(rows.select { |row| first_dips.include?(row.fetch('dataset_in_pool_id').to_i) })
      .to all(include('pool_id' => first_pool))
    expect(rows.select { |row| second_dips.include?(row.fetch('dataset_in_pool_id').to_i) })
      .to all(include('pool_id' => second_pool))

    actions = find_rows(
      :dataset_actions,
      { dataset_plan_id: plan_id, action: described_class::GROUP_SNAPSHOT_ACTION }
    )
    expect(actions.map { |row| row.fetch('pool_id') }).to contain_exactly(first_pool, second_pool)
    expect(actions.find { |row| row.fetch('pool_id') == first_pool }.fetch('id')).to eq(first_action)

    tasks = rows(:repeatable_tasks)
    expect(tasks.length).to eq(2)
    expect(tasks).to all(include(
                           'minute' => '00',
                           'hour' => '01',
                           'day_of_month' => '*',
                           'month' => '*',
                           'day_of_week' => '*'
                         ))
  end

  it 'removes duplicate memberships and is idempotent' do
    plan_id, env_plan_id = create_plan
    first_dip = create_dip(pool_id: 81, dataset_id: 801)
    second_dip = create_dip(pool_id: 82, dataset_id: 802)
    assign_plan(first_dip, env_plan_id)
    assign_plan(second_dip, env_plan_id)
    first_action = create_action(plan_id: plan_id, pool_id: 81)
    second_action = create_action(plan_id: plan_id, pool_id: 82)
    create_task(action_id: first_action)
    create_task(action_id: second_action)
    create_group(action_id: first_action, dip_id: first_dip)
    create_group(action_id: second_action, dip_id: first_dip)
    create_group(action_id: second_action, dip_id: second_dip)

    migrate_up!
    first_result = {
      actions: rows(:dataset_actions),
      groups: rows(:group_snapshots),
      tasks: rows(:repeatable_tasks)
    }
    migrate_up!

    expect(group_rows(plan_id).count { |row| row.fetch('dataset_in_pool_id').to_i == first_dip }).to eq(1)
    expect(rows(:dataset_actions)).to eq(first_result.fetch(:actions))
    expect(rows(:group_snapshots)).to eq(first_result.fetch(:groups))
    expect(rows(:repeatable_tasks)).to eq(first_result.fetch(:tasks))
  end

  it 'removes memberships for datasets without a plan assignment' do
    plan_id, env_plan_id = create_plan
    assigned = create_dip(pool_id: 150, dataset_id: 1_501)
    unassigned = create_dip(pool_id: 150, dataset_id: 1_502)
    assign_plan(assigned, env_plan_id)
    action = create_action(plan_id: plan_id, pool_id: 150)
    create_task(action_id: action)
    create_group(action_id: action, dip_id: unassigned)

    migrate_up!

    expect(group_rows(plan_id).map { |row| row.fetch('dataset_in_pool_id').to_i }).to eq([assigned])
    expect(find_rows(:group_snapshots, { dataset_in_pool_id: unassigned })).to be_empty
  end

  it 'removes all actions when the plan has no assignments' do
    plan_id, = create_plan
    dip_id = create_dip(pool_id: 250, dataset_id: 2_501)
    action = create_action(plan_id: plan_id, pool_id: 250)
    create_task(action_id: action)
    create_group(action_id: action, dip_id: dip_id)

    migrate_up!

    expect(group_rows(plan_id)).to be_empty
    expect(find_rows(:dataset_actions, { dataset_plan_id: plan_id })).to be_empty
    expect(rows(:repeatable_tasks)).to be_empty
  end

  it 'rolls back without changes when a pool has multiple destination actions' do
    plan_id, env_plan_id = create_plan
    dip_id = create_dip(pool_id: 333, dataset_id: 3_330)
    assign_plan(dip_id, env_plan_id)
    first_action = create_action(plan_id: plan_id, pool_id: 333)
    second_action = create_action(plan_id: plan_id, pool_id: 333)
    create_task(action_id: first_action)
    create_task(action_id: second_action)

    expect { migrate_up! }.to raise_error(
      ActiveRecord::MigrationError,
      /multiple daily-backup group snapshot actions for pool 333/
    )

    expect(rows(:group_snapshots)).to be_empty
    expect(rows(:dataset_actions).map { |row| row.fetch('id') }).to eq([first_action, second_action])
    expect(rows(:repeatable_tasks).length).to eq(2)
  end
end
