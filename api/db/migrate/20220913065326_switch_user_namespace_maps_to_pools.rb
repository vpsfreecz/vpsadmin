class SwitchUserNamespaceMapsToPools < ActiveRecord::Migration[6.1]
  class UserNamespaceMapNode < ActiveRecord::Base ; end
  class UserNamespaceMapPool < ActiveRecord::Base ; end
  class Node < ActiveRecord::Base ; end
  class Pool < ActiveRecord::Base ; end

  def up
    create_table :user_namespace_map_pools do |t|
      t.references  :user_namespace_map,           null: false
      t.references  :pool,                         null: false
    end

    add_index :user_namespace_map_pools, %i(user_namespace_map_id pool_id),
              unique: true, name: 'user_namespace_map_pools_unique'

    UserNamespaceMapNode.all.each do |map_on_node|
      pool = Pool.find_by!(node_id: map_on_node.node_id)

      UserNamespaceMapPool.create!(
        user_namespace_map_id: map_on_node.user_namespace_map_id,
        pool_id: pool.id,
      )
    end

    drop_table :user_namespace_map_nodes
  end

  def down
    create_table :user_namespace_map_nodes do |t|
      t.references  :user_namespace_map,  null: false
      t.references  :node,                null: false
    end

    add_index :user_namespace_map_nodes, %i(user_namespace_map_id node_id),
              unique: true, name: 'user_namespace_map_nodes_unique'

    UserNamespaceMapPool.all.each do |map_on_pool|
      pool = Pool.find(map_on_pool.pool_id)
      node = Node.find(pool.node_id)

      begin
        UserNamespaceMapNode.create!(
          user_namespace_map_id: map_on_pool.user_namespace_map_id,
          node_id: node.id,
        )
      rescue ActiveRecord::RecordNotUnique
        # One node can have multiple pools and there may already be maps on them,
        # so the rollback is imperfect. It works only in a situation where all
        # nodes have no or exactly one pool.
        next
      end
    end

    drop_table :user_namespace_map_pools
  end
end
