# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260926100000_add_bounded_storage_capture_indexes')

RSpec.describe AddBoundedStorageCaptureIndexes do
  before do
    define_schema do
      create_table :transactions do |t|
        t.integer :node_id
        t.integer :done
      end
      create_table :storage_mutation_intents do |t|
        t.integer :node_catalog_id
        t.integer :phase
      end
      create_table :storage_mutation_targets do |t|
        t.string :catalog_kind
        t.integer :catalog_id
      end
    end
  end

  it 'adds nonunique indexes for bounded node and copied catalog selection' do
    migrate_up!

    expected = {
      transactions: ['idx_transactions_node_done_id', %w[node_id done id]],
      storage_mutation_intents: ['idx_storage_intents_catalog_phase_id',
                                 %w[node_catalog_id phase id]],
      storage_mutation_targets: ['idx_storage_targets_catalog_kind_id',
                                 %w[catalog_kind catalog_id id]]
    }
    expected.each do |table, (name, columns)|
      index = connection.indexes(table).find { |candidate| candidate.name == name }
      expect(index.columns).to eq(columns)
      expect(index.unique).to be(false)
    end
  end

  it 'removes only its indexes on rollback' do
    migrate_up!
    migrate_down!

    expect(connection.indexes(:transactions).map(&:name))
      .not_to include('idx_transactions_node_done_id')
    expect(connection.indexes(:storage_mutation_intents).map(&:name))
      .not_to include('idx_storage_intents_catalog_phase_id')
    expect(connection.indexes(:storage_mutation_targets).map(&:name))
      .not_to include('idx_storage_targets_catalog_kind_id')
  end
end
