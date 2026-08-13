# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration(
  'monitoring',
  '20260813121000_remove_legacy_dns_secondary_transfer_failure_events'
)

RSpec.describe RemoveLegacyDnsSecondaryTransferFailureEvents do
  def define_monitoring_schema
    define_schema do
      create_table :monitored_events do |t|
        t.string :monitor_name, null: false
        t.string :class_name, null: false
        t.integer :row_id, null: false
      end

      create_table :monitored_event_states do |t|
        t.references :monitored_event, null: false
        t.integer :state, null: false
      end

      create_table :monitored_event_logs do |t|
        t.references :monitored_event, null: false
        t.boolean :passed, null: false
        t.string :value, null: false
      end
    end
  end

  def insert_event(monitor_name:, class_name:)
    id = insert_row(
      :monitored_events,
      monitor_name:,
      class_name:,
      row_id: 1
    )
    insert_row(:monitored_event_states, monitored_event_id: id, state: 2)
    insert_row(:monitored_event_logs, monitored_event_id: id, passed: false, value: '1')
    id
  end

  it 'removes old server-zone incidents and their history only' do
    define_monitoring_schema
    legacy_id = insert_event(
      monitor_name: 'dns_secondary_transfer_failure',
      class_name: 'DnsServerZone'
    )
    zone_id = insert_event(
      monitor_name: 'dns_secondary_transfer_failure',
      class_name: 'DnsZone'
    )
    unrelated_id = insert_event(
      monitor_name: 'other_monitor',
      class_name: 'DnsServerZone'
    )

    migrate_up!

    expect(find_rows(:monitored_events).map { |row| row.fetch('id').to_i }).to contain_exactly(
      zone_id,
      unrelated_id
    )
    expect(find_rows(:monitored_event_states).map { |row| row.fetch('monitored_event_id').to_i })
      .to contain_exactly(zone_id, unrelated_id)
    expect(find_rows(:monitored_event_logs).map { |row| row.fetch('monitored_event_id').to_i })
      .to contain_exactly(zone_id, unrelated_id)
    expect(find_rows(:monitored_events, { id: legacy_id })).to be_empty
  end

  it 'is irreversible after deleting incident history' do
    define_monitoring_schema

    expect { migrate_down! }.to raise_error(
      ActiveRecord::IrreversibleMigration,
      /cannot be reconstructed/
    )
  end
end
