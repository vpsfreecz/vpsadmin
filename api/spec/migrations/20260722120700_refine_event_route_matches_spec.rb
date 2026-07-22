# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260722120700_refine_event_route_matches')

RSpec.describe RefineEventRouteMatches do
  def define_legacy_schema
    define_schema do
      create_table :users do |t|
        t.string :login
      end

      create_table :event_routes do |t|
        t.references :user, null: false
        t.string :label
        t.integer :position, null: false, default: 0
        t.boolean :enabled, null: false, default: true
        t.integer :subject_scope, null: false, default: 0
        t.timestamps null: false
      end

      create_table :events do |t|
        t.references :user
        t.string :event_type, null: false, limit: 100
        t.string :category, null: false, limit: 100
        t.integer :severity, null: false
        t.string :subject, null: false, limit: 255
        t.integer :routing_state, null: false, default: 0
        t.bigint :matched_event_route_id
        t.timestamps null: false
      end
      add_index :events, :matched_event_route_id

      create_table :event_routing_contexts do |t|
        t.references :event, null: false
        t.references :user, null: false
        t.string :subject_relation, null: false, limit: 50
        t.string :source, null: false, limit: 50
        t.integer :routing_state, null: false
        t.bigint :matched_event_route_id
        t.timestamps null: false
      end
      add_index :event_routing_contexts, :matched_event_route_id,
                name: 'index_event_routing_contexts_on_matched_route'

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
    admin_id = insert_row(:users, login: 'admin')
    user_route_id = insert_route(user_id:, label: 'User route')
    admin_route_id = insert_route(user_id: admin_id, label: 'Admin route')
    self_event_id = insert_event(user_id:, matched_event_route_id: user_route_id, subject: 'Self event')
    visible_event_id = insert_event(user_id:, matched_event_route_id: admin_route_id, subject: 'Visible event')

    insert_context(
      event_id: self_event_id,
      user_id:,
      subject_relation: 'self',
      source: 'direct_route',
      matched_event_route_id: user_route_id
    )
    insert_context(
      event_id: visible_event_id,
      user_id: admin_id,
      subject_relation: 'other_user',
      source: 'visible_route',
      matched_event_route_id: admin_route_id
    )

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
      user_id:,
      admin_id:,
      user_route_id:,
      admin_route_id:,
      self_event_id:,
      visible_event_id:,
      default_receiver_id:,
      custom_receiver_id:,
      default_target_id:,
      custom_target_id:
    }
  end

  def insert_route(user_id:, label:)
    insert_row(
      :event_routes,
      user_id:,
      label:,
      position: 1,
      enabled: true,
      subject_scope: 0,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def insert_event(user_id:, matched_event_route_id:, subject:)
    insert_row(
      :events,
      user_id:,
      event_type: 'user.test_notification',
      category: 'test',
      severity: 0,
      subject:,
      routing_state: 1,
      matched_event_route_id:,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def insert_context(event_id:, user_id:, subject_relation:, source:, matched_event_route_id:)
    insert_row(
      :event_routing_contexts,
      event_id:,
      user_id:,
      subject_relation:,
      source:,
      routing_state: 0,
      matched_event_route_id:,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  it 'moves singular matched routes into route matches and normalizes default labels' do
    define_legacy_schema
    ids = seed_rows

    migrate_up!

    expect(table_exists?(:event_route_matches)).to be(true)
    expect(column_exists?(:events, :matched_event_route_id)).to be(false)
    expect(column_exists?(:event_routing_contexts, :matched_event_route_id)).to be(false)

    self_match = find_row(:event_route_matches, event_id: ids.fetch(:self_event_id))
    expect(self_match.fetch('event_route_id').to_i).to eq(ids.fetch(:user_route_id))
    expect(self_match.fetch('route_owner_id').to_i).to eq(ids.fetch(:user_id))
    expect(self_match.fetch('subject_relation')).to eq('self')
    expect(self_match.fetch('source')).to eq('direct_route')

    visible_match = find_row(:event_route_matches, event_id: ids.fetch(:visible_event_id))
    expect(visible_match.fetch('event_route_id').to_i).to eq(ids.fetch(:admin_route_id))
    expect(visible_match.fetch('route_owner_id').to_i).to eq(ids.fetch(:admin_id))
    expect(visible_match.fetch('subject_relation')).to eq('other_user')
    expect(visible_match.fetch('source')).to eq('visible_route')

    expect(find_row(:notification_receivers, id: ids.fetch(:default_receiver_id)).fetch('label')).to eq('Default')
    expect(find_row(:notification_receivers, id: ids.fetch(:custom_receiver_id)).fetch('label')).to eq('Default e-mail')
    expect(find_row(:notification_targets, id: ids.fetch(:default_target_id)).fetch('label')).to eq('Default')
    expect(find_row(:notification_targets, id: ids.fetch(:custom_target_id)).fetch('label')).to eq('Default e-mail')
  end

  it 'restores singular route columns on rollback' do
    define_legacy_schema
    ids = seed_rows
    migrate_up!

    migrate_down!

    expect(table_exists?(:event_route_matches)).to be(false)
    expect(column_exists?(:events, :matched_event_route_id)).to be(true)
    expect(column_exists?(:event_routing_contexts, :matched_event_route_id)).to be(true)
    expect(find_row(:events, id: ids.fetch(:self_event_id)).fetch('matched_event_route_id').to_i).to eq(
      ids.fetch(:user_route_id)
    )
    expect(find_row(:event_routing_contexts, event_id: ids.fetch(:visible_event_id)).fetch('matched_event_route_id').to_i).to eq(
      ids.fetch(:admin_route_id)
    )
    expect(find_row(:notification_receivers, id: ids.fetch(:default_receiver_id)).fetch('label')).to eq('Default e-mail')
    expect(find_row(:notification_targets, id: ids.fetch(:default_target_id)).fetch('label')).to eq('Default e-mail')
  end
end
