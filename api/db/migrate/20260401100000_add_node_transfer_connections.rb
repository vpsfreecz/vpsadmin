class AddNodeTransferConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :node_transfer_connections do |t|
      t.integer :node_a_id, null: false
      t.integer :node_b_id, null: false
      t.string :node_a_ip_addr, null: false, limit: 46
      t.string :node_b_ip_addr, null: false, limit: 46
      t.boolean :enabled, null: false, default: true
      t.timestamps null: false
    end

    add_index :node_transfer_connections,
              %i[node_a_id node_b_id],
              unique: true,
              name: 'index_ntc_on_node_pair'
    add_index :node_transfer_connections, :node_a_id, name: 'index_ntc_on_node_a_id'
    add_index :node_transfer_connections, :node_b_id, name: 'index_ntc_on_node_b_id'
  end
end
