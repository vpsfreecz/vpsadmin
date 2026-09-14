# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260914180000_add_node_kernel_event_last_confirmed_at')

RSpec.describe AddNodeKernelEventLastConfirmedAt do
  before do
    define_schema do
      create_table :node_kernel_events do |t|
        t.datetime :observed_before, null: false
      end
    end
    connection.execute("INSERT INTO node_kernel_events (observed_before) VALUES ('2026-08-22 15:33:29')")
  end

  it 'adds a nullable timestamp without a default or historical backfill and rolls back' do
    migrate_up!

    expect(column(:node_kernel_events, :last_confirmed_at).null).to be(true)
    expect(column(:node_kernel_events, :last_confirmed_at).default).to be_nil
    expect(connection.select_value('SELECT last_confirmed_at FROM node_kernel_events')).to be_nil
    expect(connection.select_value('SELECT observed_before FROM node_kernel_events'))
      .to eq(Time.utc(2026, 8, 22, 15, 33, 29))

    migrate_down!
    expect(column_exists?(:node_kernel_events, :last_confirmed_at)).to be(false)
    expect(connection.select_value('SELECT COUNT(*) FROM node_kernel_events')).to eq(1)
  end
end
