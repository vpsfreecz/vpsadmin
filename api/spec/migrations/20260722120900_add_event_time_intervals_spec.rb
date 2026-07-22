# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260722120900_add_event_time_intervals')

RSpec.describe AddEventTimeIntervals do
  def define_previous_schema
    define_schema do
      create_table :users do |t|
        t.string :login
      end

      create_table :event_routes do |t|
        t.references :user, null: false
      end

      create_table :events do |t|
        t.references :user
      end

      create_table :event_route_matches do |t|
        t.references :event, null: false
        t.references :event_route, null: false
        t.references :route_owner, null: false
        t.string :subject_relation, null: false
        t.string :source, null: false
        t.integer :match_order, null: false
        t.timestamps null: false
      end
    end
  end

  it 'adds reusable intervals, route assignments and route match audit columns' do
    define_previous_schema

    migrate_up!

    expect(table_exists?(:event_time_intervals)).to be(true)
    expect(table_exists?(:event_route_time_intervals)).to be(true)
    expect(index_exists?(:event_time_intervals, :index_event_time_intervals_on_user_name)).to be(true)
    expect(index_exists?(:event_route_time_intervals, :idx_route_time_intervals_unique)).to be(true)
    route_fk = connection.foreign_keys(:event_route_time_intervals).detect do |foreign_key|
      foreign_key.to_table == 'event_routes'
    end
    interval_fk = connection.foreign_keys(:event_route_time_intervals).detect do |foreign_key|
      foreign_key.to_table == 'event_time_intervals'
    end
    expect(route_fk&.options&.fetch(:on_delete)).to eq(:cascade)
    expect(interval_fk).to be_present
    expect(column_exists?(:event_route_matches, :time_interval_state)).to be(true)
    expect(column(:event_route_matches, :time_interval_state).default).to eq('active')
    expect(column(:event_route_matches, :time_interval_state).null).to be(false)
    expect(column_exists?(:event_route_matches, :time_interval_snapshot)).to be(true)
    expect(index_exists?(:event_route_matches, :idx_event_route_matches_on_time_state)).to be(true)
  end

  it 'cascades route assignments and restricts deletion of referenced intervals' do
    define_previous_schema
    migrate_up!
    now = timestamp
    user_id = insert_row(:users, login: 'interval-owner')
    route_id = insert_row(:event_routes, user_id:)
    interval_id = insert_row(
      :event_time_intervals,
      user_id:,
      name: 'Protected interval',
      time_zone: 'UTC',
      specs: JSON.dump([{ years: [{ start: 2026 }] }]),
      created_at: now,
      updated_at: now
    )
    insert_row(
      :event_route_time_intervals,
      event_route_id: route_id,
      event_time_interval_id: interval_id,
      mode: 0,
      created_at: now,
      updated_at: now
    )

    expect do
      connection.execute("DELETE FROM event_time_intervals WHERE id = #{interval_id}")
    end.to raise_error(ActiveRecord::InvalidForeignKey)

    connection.execute("DELETE FROM event_routes WHERE id = #{route_id}")
    expect(row_count(:event_route_time_intervals)).to eq(0)
    expect(row_count(:event_time_intervals)).to eq(1)
  end

  it 'restores the previous schema on rollback' do
    define_previous_schema
    migrate_up!

    migrate_down!

    expect(table_exists?(:event_time_intervals)).to be(false)
    expect(table_exists?(:event_route_time_intervals)).to be(false)
    expect(column_exists?(:event_route_matches, :time_interval_state)).to be(false)
    expect(column_exists?(:event_route_matches, :time_interval_snapshot)).to be(false)
  end
end
