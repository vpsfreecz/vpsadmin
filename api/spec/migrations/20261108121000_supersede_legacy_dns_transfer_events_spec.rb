# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration('monitoring', '20261108121000_supersede_legacy_dns_transfer_events')

RSpec.describe SupersedeLegacyDnsTransferEvents do
  def define_monitor_schema
    define_schema do
      create_table :monitored_events do |t|
        t.string :monitor_name
        t.string :class_name
        t.integer :state
        t.integer :alert_count, default: 0
        t.datetime :last_report_at
        t.timestamps
      end
      create_table :monitored_event_states do |t|
        t.integer :monitored_event_id
        t.integer :state
        t.datetime :created_at
      end
      create_table :monitored_event_logs do |t|
        t.integer :monitored_event_id
        t.boolean :passed
        t.string :value, limit: 255
        t.datetime :created_at
      end
    end
  end

  it 'retires only active legacy events and appends supersession without losing audit' do
    define_monitor_schema
    ids = (0..5).map do |state|
      insert_row(:monitored_events, monitor_name: 'dns_secondary_transfer_failure',
                                    class_name: 'DnsServerZone', state:, alert_count: 4,
                                    last_report_at: timestamp, created_at: timestamp, updated_at: timestamp)
    end
    unrelated = insert_row(:monitored_events, monitor_name: 'dns_primary_transfer_failure',
                                              class_name: 'DnsZone', state: 1,
                                              created_at: timestamp, updated_at: timestamp)
    prior_log = insert_row(:monitored_event_logs, monitored_event_id: ids[1], passed: false,
                                                  value: 'original evidence', created_at: timestamp)

    migrate_up!

    expect(row_count(:monitored_events)).to eq(7)
    [0, 1, 3, 4].each do |state|
      event = find_row(:monitored_events, id: ids[state])
      expect(event.fetch('state')).to eq(5)
      expect(event.fetch('alert_count')).to eq(4)
      expect(event.fetch('last_report_at')).to eq(timestamp)
      log = described_class::Observation.where(monitored_event_id: ids[state]).order(:id).last
      expect(log.value).to include('reason' => 'superseded_by_primary_readiness',
                                   'replacement_monitor' => 'dns_primary_transfer_failure')
      expect(log.passed).to be(false)
    end
    expect(find_row(:monitored_event_logs, id: prior_log).fetch('value')).to eq('original evidence')
    expect(find_row(:monitored_events, id: ids[2]).fetch('state')).to eq(2)
    expect(find_row(:monitored_events, id: unrelated).fetch('state')).to eq(1)
    expect(row_count(:monitored_event_states)).to eq(4)
  end
end
