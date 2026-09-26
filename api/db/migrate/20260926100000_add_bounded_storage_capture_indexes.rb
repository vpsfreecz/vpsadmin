class AddBoundedStorageCaptureIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :transactions, %i[node_id done id],
              name: 'idx_transactions_node_done_id'
    add_index :storage_mutation_intents, %i[node_catalog_id phase id],
              name: 'idx_storage_intents_catalog_phase_id'
    add_index :storage_mutation_targets, %i[catalog_kind catalog_id id],
              name: 'idx_storage_targets_catalog_kind_id'
  end
end
