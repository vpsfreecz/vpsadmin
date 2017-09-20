class RegisterNodePubkeys < ActiveRecord::Migration
  def change
    rename_table :node_pubkey, :node_pubkeys
    rename_column :node_pubkeys, :type, :key_type
    add_index :node_pubkeys, :node_id
  end
end
