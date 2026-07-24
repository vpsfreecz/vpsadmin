# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260722120100_add_events')

RSpec.describe AddEvents do
  def define_old_schema
    define_schema do
      create_table :users do |t|
        t.string :login, null: false
        t.string :email
        t.boolean :mailer_enabled, null: false, default: true
      end

      create_table :notification_templates do |t|
        t.string :name, null: false, limit: 100
        t.string :label, limit: 255
      end

      create_table :user_notification_template_recipients do |t|
        t.integer :user_id, null: false
        t.integer :notification_template_id, null: false
        t.string :to, limit: 500
        t.boolean :enabled, null: false, default: true
      end

      create_table :user_email_role_recipients do |t|
        t.integer :user_id, null: false
        t.string :role, limit: 100, null: false
        t.string :to, limit: 500
      end
    end
  end

  def seed_legacy_rows
    enabled_id = insert_row(:users, login: 'enabled', email: 'enabled@example.test', mailer_enabled: true)
    disabled_id = insert_row(:users, login: 'disabled', email: 'disabled@example.test', mailer_enabled: false)

    expiration_template_id = insert_row(
      :notification_templates,
      name: 'expiration_user_active',
      label: 'User expiration warning'
    )
    suspend_template_id = insert_row(
      :notification_templates,
      name: 'user_suspend',
      label: 'User account suspended'
    )

    insert_row(
      :user_notification_template_recipients,
      user_id: enabled_id,
      notification_template_id: expiration_template_id,
      to: 'expiration@example.test',
      enabled: true
    )
    insert_row(
      :user_notification_template_recipients,
      user_id: disabled_id,
      notification_template_id: suspend_template_id,
      to: 'disabled@example.test',
      enabled: true
    )

    insert_row(:user_email_role_recipients, user_id: enabled_id, role: 'account', to: 'account@example.test')
    insert_row(:user_email_role_recipients, user_id: enabled_id, role: 'admin', to: 'admin@example.test')
    insert_row(:user_email_role_recipients, user_id: disabled_id, role: 'account', to: 'disabled@example.test')

    {
      enabled_id:,
      disabled_id:
    }
  end

  it 'creates event routing tables and migrates advanced user recipients' do
    define_old_schema
    ids = seed_legacy_rows

    migrate_up!

    expect(table_exists?(:notification_receivers)).to be(true)
    expect(table_exists?(:notification_targets)).to be(true)
    expect(table_exists?(:notification_receiver_targets)).to be(true)
    expect(table_exists?(:event_routes)).to be(true)
    expect(table_exists?(:event_route_matchers)).to be(true)
    expect(table_exists?(:events)).to be(true)
    expect(table_exists?(:event_deliveries)).to be(true)
    expect(table_exists?(:event_delivery_groups)).to be(true)
    expect(table_exists?(:event_delivery_attempts)).to be(true)
    expect(column_exists?(:event_routes, :group_by)).to be(true)
    expect(column_exists?(:event_deliveries, :group_key)).to be(true)
    expect(column_exists?(:event_deliveries, :target_secret)).to be(true)

    default_receiver = find_row(:notification_receivers, user_id: ids.fetch(:enabled_id), label: 'Default e-mail')
    mute_receiver = find_row(:notification_receivers, user_id: ids.fetch(:disabled_id), label: 'Do not notify')
    expect(boolish(default_receiver.fetch('mute'))).to be(false)
    expect(boolish(mute_receiver.fetch('mute'))).to be(true)

    default_route = default_route_for(ids.fetch(:enabled_id))
    expect(default_route.fetch('notification_receiver_id').to_i).to eq(default_receiver.fetch('id').to_i)
    expect(row_count(:event_route_matchers,
                     event_route_id: default_route.fetch('id'),
                     field: 'default_routed',
                     operator: '==',
                     value: 'true')).to eq(1)
    expect(row_count(:event_route_matchers,
                     event_route_id: default_route.fetch('id'),
                     field: 'roles',
                     operator: 'contains',
                     value: 'account')).to eq(1)

    admin_default_route = default_route_for(ids.fetch(:enabled_id), role: 'admin')
    expect(admin_default_route.fetch('notification_receiver_id').to_i).to eq(default_receiver.fetch('id').to_i)
    expect(row_count(:event_route_matchers,
                     event_route_id: admin_default_route.fetch('id'),
                     field: 'roles',
                     operator: 'contains',
                     value: 'admin')).to eq(1)

    mute_route = default_route_for(ids.fetch(:disabled_id))
    expect(mute_route.fetch('notification_receiver_id').to_i).to eq(mute_receiver.fetch('id').to_i)
    expect(row_count(:event_route_matchers,
                     event_route_id: mute_route.fetch('id'),
                     field: 'default_routed',
                     operator: '==',
                     value: 'true')).to eq(1)
    expect(row_count(:event_route_matchers,
                     event_route_id: mute_route.fetch('id'),
                     field: 'roles',
                     operator: 'contains',
                     value: 'account')).to eq(1)

    admin_mute_route = default_route_for(ids.fetch(:disabled_id), role: 'admin')
    expect(admin_mute_route.fetch('notification_receiver_id').to_i).to eq(mute_receiver.fetch('id').to_i)
    expect(row_count(:event_route_matchers,
                     event_route_id: admin_mute_route.fetch('id'),
                     field: 'roles',
                     operator: 'contains',
                     value: 'admin')).to eq(1)

    account_receiver = find_row(
      :notification_receivers,
      user_id: ids.fetch(:enabled_id),
      label: 'Account management e-mail'
    )
    account_target = find_row(:notification_targets, user_id: ids.fetch(:enabled_id), target_value: 'account@example.test')
    expect(row_count(:notification_receiver_targets,
                     notification_receiver_id: account_receiver.fetch('id'),
                     notification_target_id: account_target.fetch('id'))).to eq(1)

    account_route = find_row(
      :event_routes,
      user_id: ids.fetch(:enabled_id),
      event_type: 'user.suspended',
      template_name: 'user_suspend'
    )
    expect(account_route.fetch('notification_receiver_id').to_i).to eq(account_receiver.fetch('id').to_i)
    expect(boolish(account_route.fetch('continue'))).to be(false)
    expect(row_count(:event_route_matchers,
                     event_route_id: account_route.fetch('id'),
                     field: 'roles',
                     operator: 'contains',
                     value: 'account')).to eq(1)

    admin_route = find_row(
      :event_routes,
      user_id: ids.fetch(:enabled_id),
      event_type: 'user.new_login',
      template_name: 'user_new_login'
    )
    expect(row_count(:event_route_matchers,
                     event_route_id: admin_route.fetch('id'),
                     field: 'roles',
                     operator: 'contains',
                     value: 'admin')).to eq(1)

    expiration_route = find_row(
      :event_routes,
      user_id: ids.fetch(:enabled_id),
      event_type: 'lifetime.expiration_warning',
      template_name: 'expiration_warning',
      label: 'User expiration warning e-mail'
    )
    expect(row_count(:event_route_matchers,
                     event_route_id: expiration_route.fetch('id'),
                     field: 'object',
                     operator: '==',
                     value: 'user')).to eq(1)
    expect(row_count(:event_route_matchers,
                     event_route_id: expiration_route.fetch('id'),
                     field: 'state',
                     operator: '==',
                     value: 'active')).to eq(1)

    expect(row_count(:event_routes, user_id: ids.fetch(:disabled_id), event_type: 'user.suspended')).to eq(0)
    expect(row_count(:notification_targets, user_id: ids.fetch(:disabled_id), target_value: 'disabled@example.test')).to eq(0)
  end

  def default_route_for(user_id, role: 'account')
    label = role == 'admin' ? 'Default admin route' : 'Default route'
    found = find_rows(:event_routes, { user_id:, label: }).select do |route|
      route.fetch('event_type').nil? &&
        route.fetch('event_type_pattern').nil? &&
        row_count(:event_route_matchers,
                  event_route_id: route.fetch('id'),
                  field: 'roles',
                  operator: 'contains',
                  value: role) == 1
    end

    expect(found.length).to eq(1), "expected one #{role} default route for user #{user_id}, found #{found.length}"
    found.first
  end

  it 'chains account and admin role routes for events delivered to both roles' do
    define_old_schema
    ids = seed_legacy_rows

    migrate_up!

    account_route = find_rows(
      :event_routes,
      {
        user_id: ids.fetch(:enabled_id),
        event_type: 'vps.suspended',
        template_name: 'vps_suspend'
      },
      order: :position
    ).find do |route|
      row_count(
        :event_route_matchers,
        event_route_id: route.fetch('id'),
        field: 'roles',
        operator: 'contains',
        value: 'account'
      ) == 1
    end
    admin_route = find_rows(
      :event_routes,
      {
        user_id: ids.fetch(:enabled_id),
        event_type: 'vps.suspended',
        template_name: 'vps_suspend'
      },
      order: :position
    ).find do |route|
      row_count(
        :event_route_matchers,
        event_route_id: route.fetch('id'),
        field: 'roles',
        operator: 'contains',
        value: 'admin'
      ) == 1
    end

    expect(account_route).not_to be_nil
    expect(admin_route).not_to be_nil
    expect(boolish(account_route.fetch('continue'))).to be(true)
    expect(boolish(admin_route.fetch('continue'))).to be(false)
  end

  it 'drops event routing tables on rollback' do
    define_old_schema
    seed_legacy_rows
    migrate_up!

    migrate_down!

    expect(table_exists?(:event_delivery_attempts)).to be(false)
    expect(table_exists?(:event_delivery_groups)).to be(false)
    expect(table_exists?(:event_deliveries)).to be(false)
    expect(table_exists?(:events)).to be(false)
    expect(table_exists?(:event_route_matchers)).to be(false)
    expect(table_exists?(:event_routes)).to be(false)
    expect(table_exists?(:notification_receiver_targets)).to be(false)
    expect(table_exists?(:notification_targets)).to be(false)
    expect(table_exists?(:notification_receivers)).to be(false)
  end
end
