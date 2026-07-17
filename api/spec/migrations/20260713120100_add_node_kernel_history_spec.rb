# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260713120100_add_node_kernel_history')

RSpec.describe AddNodeKernelHistory do
  before do
    define_schema do
      create_table :nodes do |t|
        t.string :domain_name
      end
    end
  end

  it 'adds the kernel event history and reconstruction checkpoint' do
    migrate_up!

    expect(table_exists?(:node_kernel_history_states)).to be(true)
    expect(column(:node_kernel_history_states, :completed_at).null).to be(false)
    history_state_index = connection.indexes(:node_kernel_history_states).find do |index|
      index.columns == ['node_id']
    end
    expect(history_state_index.unique).to be(true)
    expect(table_exists?(:node_kernel_history_gaps)).to be(true)
    expect(column(:node_kernel_history_gaps, :from).null).to be(false)
    expect(column(:node_kernel_history_gaps, :to).null).to be(false)
    expect(column_exists?(:node_kernel_history_states, :gaps)).to be(false)
    expect(table_exists?(:node_kernel_events)).to be(true)
    expect(column(:node_kernel_events, :reported_release).null).to be(false)
    expect(column(:node_kernel_events, :observed_before).null).to be(false)
    expect(column(:node_kernel_events, :current).default).to be(false)
    expect(column_exists?(:node_kernel_events, :source_status_id)).to be(true)
    expect(column_exists?(:node_kernel_events, :evidence)).to be(false)
    expect(index_exists?(:node_kernel_events, %i[node_id observed_before])).to be(true)
    expect(index_exists?(:node_kernel_events, %i[node_id boot_id])).to be(true)
    expect(index_exists?(:node_kernel_events, %i[node_id current])).to be(true)
    source_index = connection.indexes(:node_kernel_events).find do |index|
      index.name == 'idx_node_kernel_events_source_status'
    end
    expect(source_index.columns).to eq(%w[node_id source_status_id event_type])
    expect(source_index.unique).to be(true)
  end

  it 'removes history storage on rollback' do
    migrate_up!

    migrate_down!

    expect(table_exists?(:node_kernel_events)).to be(false)
    expect(table_exists?(:node_kernel_history_gaps)).to be(false)
    expect(table_exists?(:node_kernel_history_states)).to be(false)
  end
end
