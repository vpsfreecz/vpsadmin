# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260722121000_migrate_oom_report_rules_to_routes')

RSpec.describe MigrateOomReportRulesToRoutes do
  def define_legacy_schema
    define_schema do
      create_table :users do |t|
        t.string :login, null: false
      end

      create_table :vpses do |t|
        t.references :user, null: false
        t.string :hostname
        t.bigint :implicit_oom_report_rule_hit_count, null: false, default: 0
      end

      create_table :oom_report_rules do |t|
        t.references :vps, null: false
        t.integer :action, null: false
        t.string :cgroup_pattern, null: false
        t.bigint :hit_count, null: false, default: 0
        t.timestamps null: false
      end

      create_table :oom_reports do |t|
        t.references :vps, null: false
        t.bigint :oom_report_rule_id
        t.datetime :reported_at
        t.boolean :ignored, null: false, default: false
      end
      add_index :oom_reports, :reported_at

      create_table :notification_receivers do |t|
        t.references :user, null: false
        t.string :label, null: false, limit: 255
        t.text :description
        t.boolean :enabled, null: false, default: true
        t.boolean :mute, null: false, default: false
        t.timestamps null: false
      end

      create_table :event_routes do |t|
        t.references :user, null: false
        t.bigint :parent_id
        t.bigint :notification_receiver_id
        t.string :label, limit: 255
        t.integer :position, null: false, default: 0
        t.boolean :enabled, null: false, default: true
        t.string :event_type, limit: 100
        t.string :event_type_pattern, limit: 100
        t.string :template_name, limit: 100
        t.integer :subject_scope, null: false, default: 0
        t.boolean :grouping_enabled, null: false, default: false
        t.text :group_by
        t.integer :group_wait_seconds
        t.integer :group_interval_seconds
        t.boolean :continue, null: false, default: false
        t.boolean :single_use, null: false, default: false
        t.datetime :spent_at
        t.datetime :expires_at
        t.bigint :hit_count, null: false, default: 0
        t.timestamps null: false
      end

      create_table :event_route_matchers do |t|
        t.references :event_route, null: false
        t.string :field, null: false, limit: 100
        t.string :operator, null: false, limit: 50
        t.text :value, null: false
        t.timestamps null: false
      end
    end
  end

  def create_user_with_defaults(login)
    user_id = insert_row(:users, login:)
    receiver_id = insert_row(
      :notification_receivers,
      user_id:,
      label: 'Default e-mail',
      description: 'Default receiver',
      enabled: true,
      mute: false,
      created_at: timestamp,
      updated_at: timestamp
    )
    default_route_id = insert_route(
      user_id:,
      receiver_id:,
      label: 'Default route',
      position: 10_000
    )
    admin_route_id = insert_route(
      user_id:,
      receiver_id:,
      label: 'Default admin route',
      position: 10_001
    )

    {
      user_id:,
      receiver_id:,
      default_route_id:,
      admin_route_id:
    }
  end

  def insert_route(user_id:, receiver_id:, label:, position:, event_type: nil)
    insert_row(
      :event_routes,
      user_id:,
      parent_id: nil,
      notification_receiver_id: receiver_id,
      label:,
      position:,
      enabled: true,
      event_type:,
      event_type_pattern: nil,
      template_name: nil,
      subject_scope: 0,
      grouping_enabled: false,
      group_by: nil,
      group_wait_seconds: nil,
      group_interval_seconds: nil,
      continue: false,
      single_use: false,
      spent_at: nil,
      expires_at: nil,
      hit_count: 0,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def create_vps(user_id, hostname)
    insert_row(
      :vpses,
      user_id:,
      hostname:,
      implicit_oom_report_rule_hit_count: 12
    )
  end

  def create_rule(vps_id:, action:, pattern:, hit_count:)
    insert_row(
      :oom_report_rules,
      vps_id:,
      action:,
      cgroup_pattern: pattern,
      hit_count:,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def expect_matcher(route_id, field, operator, value)
    expect(row_count(
             :event_route_matchers,
             event_route_id: route_id,
             field:,
             operator:,
             value:
           )).to eq(1)
  end

  it 'preserves ordered notify and ignore semantics before the default routes' do
    define_legacy_schema
    first_user = create_user_with_defaults('first')
    second_user = create_user_with_defaults('second')
    legacy_oom_receiver_id = insert_row(
      :notification_receivers,
      user_id: first_user.fetch(:user_id),
      label: 'Legacy OOM recipient',
      description: 'Advanced OOM recipient',
      enabled: true,
      mute: false,
      created_at: timestamp,
      updated_at: timestamp
    )
    legacy_oom_route_id = insert_route(
      user_id: first_user.fetch(:user_id),
      receiver_id: legacy_oom_receiver_id,
      label: 'Legacy OOM notification',
      position: 5,
      event_type: 'vps.oom_report'
    )
    first_vps = create_vps(first_user.fetch(:user_id), 'first-vps')
    second_vps = create_vps(second_user.fetch(:user_id), 'second-vps')
    broad_rule_id = create_rule(
      vps_id: first_vps,
      action: 0,
      pattern: '/user.slice/*',
      hit_count: 41
    )
    narrow_rule_id = create_rule(
      vps_id: first_vps,
      action: 1,
      pattern: '/user.slice/special.scope',
      hit_count: 7
    )
    other_rule_id = create_rule(
      vps_id: second_vps,
      action: 1,
      pattern: '/system.slice/{a,b}.service',
      hit_count: 3
    )
    report_id = insert_row(
      :oom_reports,
      vps_id: first_vps,
      oom_report_rule_id: narrow_rule_id,
      ignored: true
    )

    migrate_up!

    expect(table_exists?(:oom_report_rules)).to be(false)
    expect(column_exists?(:oom_reports, :oom_report_rule_id)).to be(false)
    expect(column_exists?(:oom_reports, :reported_at)).to be(false)
    expect(column_exists?(:vpses, :implicit_oom_report_rule_hit_count)).to be(false)
    expect(column_exists?(:oom_reports, :ignored)).to be(true)
    expect(find_row(:oom_reports, id: report_id).fetch('ignored')).to be_truthy

    first_routes = find_rows(
      :event_routes,
      {
        user_id: first_user.fetch(:user_id),
        event_type: 'vps.oom_report'
      },
      order: %i[position id]
    )
    expect(first_routes.map { |route| route.fetch('label') }).to eq(
      [
        'OOM report notify /user.slice/*',
        'OOM report ignore /user.slice/special.scope',
        'OOM report notifications'
      ]
    )
    expect(first_routes.map { |route| route.fetch('hit_count').to_i }).to eq([41, 7, 12])
    expect(first_routes.map { |route| route.fetch('position').to_i }).to eq([0, 1, 2])
    expect(first_routes.map { |route| boolish(route.fetch('continue')) }).to eq([false, false, false])

    notify_route, ignore_route, catch_all_route = first_routes
    expect(notify_route.fetch('notification_receiver_id').to_i)
      .to eq(legacy_oom_receiver_id)
    ignored_receiver = find_row(
      :notification_receivers,
      user_id: first_user.fetch(:user_id),
      label: 'Ignored OOM reports'
    )
    expect(boolish(ignored_receiver.fetch('enabled'))).to be(true)
    expect(boolish(ignored_receiver.fetch('mute'))).to be(true)
    expect(ignore_route.fetch('notification_receiver_id').to_i)
      .to eq(ignored_receiver.fetch('id').to_i)
    expect(catch_all_route.fetch('notification_receiver_id').to_i)
      .to eq(legacy_oom_receiver_id)
    expect(row_count(:event_routes, id: legacy_oom_route_id)).to eq(0)

    expect_matcher(notify_route.fetch('id'), 'vps_id', '==', first_vps.to_s)
    expect_matcher(notify_route.fetch('id'), 'cgroup', '=*', '/user.slice/*')
    expect_matcher(ignore_route.fetch('id'), 'vps_id', '==', first_vps.to_s)
    expect_matcher(
      ignore_route.fetch('id'),
      'cgroup',
      '=*',
      '/user.slice/special.scope'
    )
    expect(boolish(notify_route.fetch('grouping_enabled'))).to be(true)
    expect(JSON.parse(notify_route.fetch('group_by'))).to eq(['vps_id'])
    expect(notify_route.fetch('group_wait_seconds').to_i).to eq(60)
    expect(notify_route.fetch('group_interval_seconds').to_i).to eq(10_800)
    expect(boolish(ignore_route.fetch('grouping_enabled'))).to be(false)
    expect(boolish(catch_all_route.fetch('grouping_enabled'))).to be(true)
    expect(row_count(
             :event_route_matchers,
             event_route_id: catch_all_route.fetch('id')
           )).to eq(0)

    default_route = find_row(
      :event_routes,
      id: first_user.fetch(:default_route_id)
    )
    admin_route = find_row(
      :event_routes,
      id: first_user.fetch(:admin_route_id)
    )
    expect(default_route.fetch('position').to_i).to eq(10_003)
    expect(admin_route.fetch('position').to_i).to eq(10_004)

    other_route = find_row(
      :event_routes,
      user_id: second_user.fetch(:user_id),
      event_type: 'vps.oom_report',
      label: 'OOM report ignore /system.slice/{a,b}.service'
    )
    expect(other_route.fetch('hit_count').to_i).to eq(3)
    expect_matcher(
      other_route.fetch('id'),
      'cgroup',
      '=*',
      '/system.slice/{a,b}.service'
    )
    expect([broad_rule_id, narrow_rule_id, other_rule_id]).to all(be_positive)
  end

  it 'migrates more rules than the normal per-user route creation limit' do
    define_legacy_schema
    user = create_user_with_defaults('many-rules')
    vps_id = create_vps(user.fetch(:user_id), 'many-rules-vps')

    101.times do |i|
      create_rule(
        vps_id:,
        action: i.odd? ? 1 : 0,
        pattern: "/user.slice/rule-#{i}.scope",
        hit_count: i
      )
    end

    migrate_up!

    routes = find_rows(
      :event_routes,
      {
        user_id: user.fetch(:user_id),
        event_type: 'vps.oom_report'
      },
      order: %i[position id]
    )
    expect(routes.length).to eq(102)
    expect(routes.first(101).map { |route| route.fetch('hit_count').to_i }).to eq((0..100).to_a)
    expect(routes.last.fetch('label')).to eq('OOM report notifications')
    expect(row_count(:event_route_matchers)).to eq(202)
  end

  it 'keeps the legacy schema when a source rule cannot be converted' do
    define_legacy_schema
    user_id = insert_row(:users, login: 'missing-default')
    vps_id = create_vps(user_id, 'missing-default-vps')
    create_rule(
      vps_id:,
      action: 0,
      pattern: '/user.slice/*',
      hit_count: 1
    )

    expect { migrate_up! }
      .to raise_error(ActiveRecord::MigrationError, /default admin receiver missing/)

    expect(table_exists?(:oom_report_rules)).to be(true)
    expect(column_exists?(:oom_reports, :oom_report_rule_id)).to be(true)
    expect(column_exists?(:vpses, :implicit_oom_report_rule_hit_count)).to be(true)
  end

  it 'is irreversible after deleting legacy rule storage' do
    define_legacy_schema
    user = create_user_with_defaults('rollback')
    vps_id = create_vps(user.fetch(:user_id), 'rollback-vps')
    create_rule(
      vps_id:,
      action: 1,
      pattern: '/rollback/*',
      hit_count: 9
    )

    migrate_up!

    expect { migrate_down! }
      .to raise_error(ActiveRecord::IrreversibleMigration, /database backup/)
  end
end
