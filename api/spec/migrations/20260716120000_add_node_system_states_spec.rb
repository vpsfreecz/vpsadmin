# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260716120000_add_node_system_states')

RSpec.describe AddNodeSystemStates do
  before do
    define_schema do
      create_table :nodes do |t|
        t.integer :cpus, null: false
        t.integer :total_memory, null: false
        t.integer :total_swap, null: false
      end
    end
  end

  it 'adds normalized system-state history' do
    migrate_up!

    expect(table_exists?(:node_system_history_states)).to be(true)
    expect(column(:node_system_history_states, :completed_at).null).to be(false)
    checkpoint_index = connection.indexes(:node_system_history_states).find do |index|
      index.columns == ['node_id']
    end
    expect(checkpoint_index.unique).to be(true)
    expect(column_exists?(:node_system_history_states, :from_status_id)).to be(true)
    expect(column_exists?(:node_system_history_states, :through_status_id)).to be(true)
    expect(column_exists?(:node_system_history_states, :started_at)).to be(true)
    expect(column_exists?(:node_system_history_states, :observed_through)).to be(true)
    expect(table_exists?(:node_system_states)).to be(true)
    expect(column(:node_system_states, :cpus).null).to be(true)
    expect(column(:node_system_states, :first_observed_at).null).to be(false)
    expect(column(:node_system_states, :last_observed_at).null).to be(false)
    expect(column(:node_system_states, :current).default).to be(false)
    expect(index_exists?(:node_system_states, %i[node_id first_observed_at])).to be(true)
    expect(index_exists?(:node_system_states, %i[node_id current])).to be(true)
  end

  it 'removes system-state history on rollback' do
    migrate_up!
    migrate_down!

    expect(table_exists?(:node_system_history_states)).to be(false)
    expect(table_exists?(:node_system_states)).to be(false)
  end
end
