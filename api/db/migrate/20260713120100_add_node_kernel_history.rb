class AddNodeKernelHistory < ActiveRecord::Migration[8.1]
  def change
    create_table :node_kernel_history_states do |t|
      t.references :node, null: false, index: { unique: true }
      t.bigint :from_status_id
      t.bigint :through_status_id
      t.datetime :started_at
      t.datetime :observed_through
      t.datetime :completed_at, null: false
      t.timestamps
    end

    create_table :node_kernel_history_gaps do |t|
      t.references :node_kernel_history_state,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.datetime :from, null: false
      t.datetime :to, null: false
      t.string :reason, null: false
      t.timestamps
    end

    add_index :node_kernel_history_gaps,
              %i[node_kernel_history_state_id from to],
              name: :idx_node_kernel_history_gaps_interval

    create_table :node_kernel_events do |t|
      t.references :node, null: false
      t.bigint :source_status_id
      t.integer :event_type, null: false
      t.integer :source, null: false
      t.integer :confidence, null: false
      t.string :boot_id, limit: 64
      t.datetime :booted_at
      t.string :booted_release, limit: 128
      t.string :reported_release, null: false, limit: 128
      t.datetime :effective_at
      t.datetime :observed_after
      t.datetime :observed_before, null: false
      t.boolean :current, null: false, default: false
      t.timestamps
    end

    add_index :node_kernel_events, %i[node_id observed_before]
    add_index :node_kernel_events, %i[node_id boot_id]
    add_index :node_kernel_events, %i[node_id current]
    add_index :node_kernel_events,
              %i[node_id source_status_id event_type],
              unique: true,
              name: 'idx_node_kernel_events_source_status'
  end
end
