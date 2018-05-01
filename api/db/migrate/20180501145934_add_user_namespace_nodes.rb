class AddUserNamespaceNodes < ActiveRecord::Migration
  def change
    create_table :user_namespace_nodes do |t|
      t.references :user_namespace, null: false
      t.references :node,           null: false
    end

    add_index :user_namespace_nodes, :user_namespace_id
    add_index :user_namespace_nodes, :node_id
    add_index :user_namespace_nodes, %i(user_namespace_id node_id), unique: true
  end
end
