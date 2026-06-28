# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260623210000_remove_users_mailer_enabled')

RSpec.describe RemoveUsersMailerEnabled do
  def define_notification_schema
    define_schema do
      create_table :users do |t|
        t.string :login, null: false
        t.string :email
        t.boolean :mailer_enabled, null: false, default: true
      end

      create_table :user_notification_delivery_methods do |t|
        t.references :user, null: false, index: false
        t.string :delivery_method, limit: 32, null: false
        t.boolean :enabled, null: false, default: true
        t.timestamps null: false
      end

      create_table :notification_receivers do |t|
        t.references :user, null: false
        t.string :label, null: false, limit: 255
        t.text :description
        t.boolean :enabled, null: false, default: true
        t.boolean :mute, null: false, default: false
        t.timestamps null: false
      end

      create_table :notification_targets do |t|
        t.references :user, null: false
        t.string :action, null: false, limit: 50
        t.string :label, limit: 255
        t.integer :target_kind, null: false, default: 0
        t.text :target_value
        t.string :identity_key, limit: 255
        t.boolean :enabled, null: false, default: true
        t.datetime :verified_at
        t.timestamps null: false
      end

      create_table :notification_receiver_targets do |t|
        t.references :notification_receiver, null: false
        t.references :notification_target, null: false
        t.integer :position, null: false, default: 0
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
        t.boolean :continue, null: false, default: false
        t.boolean :default_route, null: false, default: false
        t.boolean :single_use, null: false, default: false
        t.datetime :spent_at
        t.datetime :expires_at
        t.bigint :hit_count, null: false, default: 0
        t.timestamps null: false
      end
    end
  end

  def seed_users
    enabled_id = insert_row(:users, login: 'enabled', email: 'enabled@example.test', mailer_enabled: true)
    disabled_id = insert_row(:users, login: 'disabled', email: 'disabled@example.test', mailer_enabled: false)
    existing_method_id = insert_row(:users, login: 'existing', email: 'existing@example.test', mailer_enabled: false)
    legacy_mute_id = insert_row(:users, login: 'legacy', email: 'legacy@example.test', mailer_enabled: false)

    insert_row(
      :user_notification_delivery_methods,
      user_id: existing_method_id,
      delivery_method: 'email',
      enabled: true,
      created_at: timestamp,
      updated_at: timestamp
    )
    insert_row(
      :notification_receivers,
      user_id: legacy_mute_id,
      label: 'Do not notify',
      description: 'Created from the disabled mailer setting',
      enabled: true,
      mute: true,
      created_at: timestamp,
      updated_at: timestamp
    )

    {
      enabled_id:,
      disabled_id:,
      existing_method_id:,
      legacy_mute_id:
    }
  end

  it 'preserves disabled mailers in delivery methods and default routes' do
    define_notification_schema
    ids = seed_users

    migrate_up!

    expect(column_exists?(:users, :mailer_enabled)).to be(false)

    disabled_method = find_row(
      :user_notification_delivery_methods,
      user_id: ids.fetch(:disabled_id),
      delivery_method: 'email'
    )
    existing_method = find_row(
      :user_notification_delivery_methods,
      user_id: ids.fetch(:existing_method_id),
      delivery_method: 'email'
    )
    expect(boolish(disabled_method.fetch('enabled'))).to be(false)
    expect(boolish(existing_method.fetch('enabled'))).to be(false)

    enabled_route = find_row(:event_routes, user_id: ids.fetch(:enabled_id), default_route: true)
    enabled_receiver = find_row(:notification_receivers, id: enabled_route.fetch('notification_receiver_id'))
    expect(enabled_receiver.fetch('label')).to eq('Default e-mail')
    expect(boolish(enabled_receiver.fetch('mute'))).to be(false)

    disabled_route = find_row(:event_routes, user_id: ids.fetch(:disabled_id), default_route: true)
    disabled_receiver = find_row(:notification_receivers, id: disabled_route.fetch('notification_receiver_id'))
    expect(disabled_receiver.fetch('label')).to eq('Mute')
    expect(boolish(disabled_receiver.fetch('mute'))).to be(true)

    legacy_mute = find_row(:notification_receivers, user_id: ids.fetch(:legacy_mute_id), mute: true)
    expect(legacy_mute.fetch('label')).to eq('Mute')
    expect(legacy_mute.fetch('description')).to eq('Default muted notification receiver')

    expect(row_count(:notification_targets, action: 'email', identity_key: 'default')).to eq(4)
    expect(row_count(:notification_receiver_targets)).to eq(4)
  end

  it 'restores mailer_enabled from disabled delivery methods on rollback' do
    define_notification_schema
    ids = seed_users
    migrate_up!

    migrate_down!

    expect(column_exists?(:users, :mailer_enabled)).to be(true)
    expect(boolish(find_row(:users, id: ids.fetch(:enabled_id)).fetch('mailer_enabled'))).to be(true)
    expect(boolish(find_row(:users, id: ids.fetch(:disabled_id)).fetch('mailer_enabled'))).to be(false)
    expect(boolish(find_row(:users, id: ids.fetch(:existing_method_id)).fetch('mailer_enabled'))).to be(false)
  end
end
