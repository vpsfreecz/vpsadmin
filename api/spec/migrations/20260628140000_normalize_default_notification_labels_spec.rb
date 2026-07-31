# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260628140000_normalize_default_notification_labels')

RSpec.describe NormalizeDefaultNotificationLabels do
  def define_legacy_schema
    define_schema do
      create_table :users do |t|
        t.string :login
      end

      create_table :notification_receivers do |t|
        t.references :user, null: false
        t.string :label, null: false
        t.text :description
        t.boolean :enabled, null: false, default: true
        t.boolean :mute, null: false, default: false
        t.timestamps null: false
      end

      create_table :notification_targets do |t|
        t.references :user, null: false
        t.string :action, null: false, limit: 50
        t.string :label
        t.integer :target_kind, null: false, default: 0
        t.string :identity_key
        t.boolean :enabled, null: false, default: true
        t.timestamps null: false
      end
    end
  end

  def seed_rows
    user_id = insert_row(:users, login: 'member')
    default_receiver_id = insert_row(
      :notification_receivers,
      user_id:,
      label: 'Default e-mail',
      description: 'Default notification receiver',
      enabled: true,
      mute: false,
      created_at: timestamp,
      updated_at: timestamp
    )
    custom_receiver_id = insert_row(
      :notification_receivers,
      user_id:,
      label: 'Default e-mail',
      description: 'Custom label that should stay unchanged',
      enabled: true,
      mute: false,
      created_at: timestamp,
      updated_at: timestamp
    )
    default_target_id = insert_row(
      :notification_targets,
      user_id:,
      action: 'email',
      label: 'Default e-mail',
      target_kind: 0,
      identity_key: 'default',
      enabled: true,
      created_at: timestamp,
      updated_at: timestamp
    )
    custom_target_id = insert_row(
      :notification_targets,
      user_id:,
      action: 'email',
      label: 'Default e-mail',
      target_kind: 1,
      identity_key: 'custom:legacy',
      enabled: true,
      created_at: timestamp,
      updated_at: timestamp
    )

    {
      default_receiver_id:,
      custom_receiver_id:,
      default_target_id:,
      custom_target_id:
    }
  end

  it 'normalizes generated default receiver and target labels' do
    define_legacy_schema
    ids = seed_rows

    migrate_up!

    expect(find_row(:notification_receivers, id: ids.fetch(:default_receiver_id)).fetch('label')).to eq('Default')
    expect(find_row(:notification_receivers, id: ids.fetch(:custom_receiver_id)).fetch('label')).to eq('Default e-mail')
    expect(find_row(:notification_targets, id: ids.fetch(:default_target_id)).fetch('label')).to eq('Default')
    expect(find_row(:notification_targets, id: ids.fetch(:custom_target_id)).fetch('label')).to eq('Default e-mail')
  end

  it 'restores generated default labels on rollback' do
    define_legacy_schema
    ids = seed_rows
    migrate_up!

    migrate_down!

    expect(find_row(:notification_receivers, id: ids.fetch(:default_receiver_id)).fetch('label')).to eq('Default e-mail')
    expect(find_row(:notification_targets, id: ids.fetch(:default_target_id)).fetch('label')).to eq('Default e-mail')
  end
end
