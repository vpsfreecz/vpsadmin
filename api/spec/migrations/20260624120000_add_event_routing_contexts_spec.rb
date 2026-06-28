# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260624120000_add_event_routing_contexts')

RSpec.describe AddEventRoutingContexts do
  def define_event_schema
    define_schema do
      create_table :users do |t|
        t.string :login
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

      create_table :event_deliveries do |t|
        t.references :event, null: false
        t.references :event_route
        t.integer :state, null: false
        t.string :action, null: false, limit: 50
        t.integer :target_kind, null: false, default: 0
        t.timestamps null: false
      end
    end
  end

  def seed_deliveries
    user_id = insert_row(:users, login: 'member')
    admin_id = insert_row(:users, login: 'admin')

    user_route_id = insert_event_route(user_id:, label: 'User route')
    admin_route_id = insert_event_route(user_id: admin_id, label: 'Admin visible route')

    self_event_id = insert_event(user_id:, matched_event_route_id: user_route_id, subject: 'Self event')
    other_event_id = insert_event(user_id:, matched_event_route_id: admin_route_id, subject: 'Other event')
    system_event_id = insert_event(user_id: nil, matched_event_route_id: admin_route_id, subject: 'System event')

    self_delivery_id = insert_delivery(event_id: self_event_id, event_route_id: user_route_id, state: 4)
    other_delivery_id = insert_delivery(event_id: other_event_id, event_route_id: admin_route_id, state: 5)
    system_delivery_id = insert_delivery(event_id: system_event_id, event_route_id: admin_route_id, state: 0)

    {
      user_id:,
      admin_id:,
      user_route_id:,
      admin_route_id:,
      self_event_id:,
      other_event_id:,
      system_event_id:,
      self_delivery_id:,
      other_delivery_id:,
      system_delivery_id:
    }
  end

  def insert_event_route(user_id:, label:)
    insert_row(
      :event_routes,
      user_id:,
      parent_id: nil,
      notification_receiver_id: nil,
      label:,
      position: 1,
      enabled: true,
      event_type: nil,
      event_type_pattern: nil,
      template_name: nil,
      continue: false,
      default_route: false,
      single_use: false,
      spent_at: nil,
      expires_at: nil,
      hit_count: 0,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def insert_event(user_id:, matched_event_route_id:, subject:)
    insert_row(
      :events,
      user_id:,
      event_type: 'test.event',
      category: 'test',
      severity: 1,
      subject:,
      routing_state: 0,
      matched_event_route_id:,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  def insert_delivery(event_id:, event_route_id:, state:)
    insert_row(
      :event_deliveries,
      event_id:,
      event_route_id:,
      state:,
      action: 'email',
      target_kind: 0,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  it 'backfills routing contexts for existing deliveries' do
    define_event_schema
    ids = seed_deliveries

    migrate_up!

    expect(column_exists?(:event_routes, :subject_scope)).to be(true)
    expect(table_exists?(:event_routing_contexts)).to be(true)
    expect(column_exists?(:event_deliveries, :event_routing_context_id)).to be(true)

    self_context = find_row(:event_routing_contexts, event_id: ids.fetch(:self_event_id))
    expect(self_context.fetch('user_id').to_i).to eq(ids.fetch(:user_id))
    expect(self_context.fetch('subject_relation')).to eq('self')
    expect(self_context.fetch('source')).to eq('direct_route')
    expect(self_context.fetch('routing_state').to_i).to eq(1)

    other_context = find_row(:event_routing_contexts, event_id: ids.fetch(:other_event_id))
    expect(other_context.fetch('user_id').to_i).to eq(ids.fetch(:admin_id))
    expect(other_context.fetch('subject_relation')).to eq('other_user')
    expect(other_context.fetch('source')).to eq('visible_route')
    expect(other_context.fetch('routing_state').to_i).to eq(2)

    system_context = find_row(:event_routing_contexts, event_id: ids.fetch(:system_event_id))
    expect(system_context.fetch('user_id').to_i).to eq(ids.fetch(:admin_id))
    expect(system_context.fetch('subject_relation')).to eq('system')
    expect(system_context.fetch('source')).to eq('system_route')
    expect(system_context.fetch('routing_state').to_i).to eq(0)

    delivery = find_row(:event_deliveries, id: ids.fetch(:system_delivery_id))
    expect(delivery.fetch('event_routing_context_id').to_i).to eq(system_context.fetch('id').to_i)
  end

  it 'rolls back the routing context schema' do
    define_event_schema
    seed_deliveries
    migrate_up!

    migrate_down!

    expect(table_exists?(:event_routing_contexts)).to be(false)
    expect(column_exists?(:event_deliveries, :event_routing_context_id)).to be(false)
    expect(column_exists?(:event_routes, :subject_scope)).to be(false)
  end
end
