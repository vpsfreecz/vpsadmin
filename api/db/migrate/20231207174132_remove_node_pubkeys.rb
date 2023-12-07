class RemoveNodePubkeys < ActiveRecord::Migration[7.0]
  def up
    drop_table :node_pubkeys
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
