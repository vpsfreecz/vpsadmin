class RemoveUserNamespaceMapPools < ActiveRecord::Migration[6.1]
  def up
    drop_table :user_namespace_map_pools
  end

  def down
    create_table :user_namespace_map_pools do |t|
      t.references  :user_namespace_map,           null: false
      t.references  :pool,                         null: false
    end

    add_index :user_namespace_map_pools, %i(user_namespace_map_id pool_id),
              unique: true, name: 'user_namespace_map_pools_unique'
  end
end
