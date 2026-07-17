class AddNodeSystemStates < ActiveRecord::Migration[8.1]
  def change
    create_table :node_system_states do |t|
      t.references :node, null: false
      t.integer :cpus
      t.integer :total_memory
      t.integer :total_swap
      t.integer :cgroup_version
      t.datetime :first_observed_at, null: false
      t.datetime :last_observed_at, null: false
      t.boolean :current, null: false, default: false
      t.timestamps
    end

    add_index :node_system_states, %i[node_id first_observed_at],
              name: 'idx_node_system_states_observed'
    add_index :node_system_states, %i[node_id current],
              name: 'idx_node_system_states_current'

    create_table :node_system_history_states do |t|
      t.references :node, null: false, index: { unique: true }
      t.bigint :from_status_id
      t.bigint :through_status_id
      t.datetime :started_at
      t.datetime :observed_through
      t.datetime :completed_at, null: false
      t.timestamps
    end
  end
end
