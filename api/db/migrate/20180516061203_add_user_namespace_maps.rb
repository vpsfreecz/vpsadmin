class AddUserNamespaceMaps < ActiveRecord::Migration
  class UserNamespace < ActiveRecord::Base ; end
  class UserNamespaceMap < ActiveRecord::Base ; end
  class UserNamespaceMapEntry < ActiveRecord::Base ; end
  class UserNamespaceMapUgid < ActiveRecord::Base ; end

  def up
    create_table :user_namespace_maps do |t|
      t.references :user_namespace,          null: false
      t.references :user_namespace_map_ugid, null: false
      t.string     :label,                   null: false
    end

    add_index :user_namespace_maps, :user_namespace_id
    add_index :user_namespace_maps, :user_namespace_map_ugid_id, unique: true

    create_table :user_namespace_map_entries do |t|
      t.references :user_namespace_map,      null: false
      t.integer    :kind,                    null: false
      t.integer    :ns_id,                   null: false, unsigned: true
      t.integer    :host_id,                 null: false, unsigned: true
      t.integer    :count,                   null: false, unsigned: true
    end

    add_index :user_namespace_map_entries, :user_namespace_map_id

    create_table :user_namespace_map_nodes do |t|
      t.references :user_namespace_map,  null: false
      t.references :node,                null: false
    end

    add_index :user_namespace_map_nodes, :user_namespace_map_id
    add_index :user_namespace_map_nodes, :node_id
    add_index :user_namespace_map_nodes, %i(user_namespace_map_id node_id),
              unique: true, name: 'user_namespace_map_nodes_unique'

    add_column :dataset_in_pools, :user_namespace_map_id, :integer, null: true
    add_index :dataset_in_pools, :user_namespace_map_id

    create_table :user_namespace_map_ugids do |t|
      t.references :user_namespace_map,  null: true
      t.integer    :ugid,                null: false, unsigned: true
    end

    add_index :user_namespace_map_ugids, :user_namespace_map_id, unique: true
    add_index :user_namespace_map_ugids, :ugid, unique: true

    # Copy UGIDs to the new table
    ActiveRecord::Base.connection.execute(
      'INSERT INTO user_namespace_map_ugids (user_namespace_map_id, ugid)
      SELECT user_namespace_id, ugid FROM user_namespace_ugids
      ORDER BY id'
    )

    # Create a default map for each user namespace, with the same id so that
    # osctl users will remain valid
    UserNamespace.all.each do |uns|
      map = UserNamespaceMap.create!(
        id: uns.id,
        user_namespace_id: uns.id,
        user_namespace_map_ugid_id: UserNamespaceMapUgid.find_by!(
          user_namespace_map_id: uns.id
        ).id,
        label: 'Default map',
      )

      [0, 1].each do |kind|
        UserNamespaceMapEntry.create!(
          user_namespace_map_id: map.id,
          kind: kind,
          ns_id: 0,
          host_id: 0,
          count: uns.size,
        )
      end
    end

    # Copy user namespace nodes to the new table
    ActiveRecord::Base.connection.execute(
      'INSERT INTO user_namespace_map_nodes (user_namespace_map_id, node_id)
      SELECT user_namespace_id, node_id FROM user_namespace_nodes'
    )

    # Switch dataset_in_pools from namespaces to maps
    ActiveRecord::Base.connection.execute(
      'UPDATE dataset_in_pools SET user_namespace_map_id = user_namespace_id'
    )

    # Cleanup
    remove_column :dataset_in_pools, :user_namespace_id
    remove_column :user_namespaces, :user_namespace_ugid_id
    drop_table :user_namespace_nodes
    drop_table :user_namespace_ugids
  end

  def down
    # Reversing this migration is too much of unnecessary work
    raise ActiveRecord::IrreversibleMigration

    create_table :user_namespace_ugids do |t|
      t.references :user_namespace,      null: true
      t.integer    :ugid,                null: false, unsigned: true
    end

    add_index :user_namespace_ugids, :user_namespace_id, unique: true
    add_index :user_namespace_ugids, :ugid, unique: true

    create_table :user_namespace_nodes do |t|
      t.references :user_namespace, null: false
      t.references :node,           null: false
    end

    add_index :user_namespace_nodes, :user_namespace_id
    add_index :user_namespace_nodes, :node_id
    add_index :user_namespace_nodes, %i(user_namespace_id node_id), unique: true

    add_column :dataset_in_pools, :user_namespace_id, :integer, null: true
    add_index :dataset_in_pools, :user_namespace_id

    add_column :user_namespaces, :user_namespace_ugid_id, :integer, null: true
    add_index :user_namespaces, :user_namespace_ugid_id, unique: true

    # The following would have to be implemented:
    # - squash multiple maps into single namespace, nodes will remain broken,
    #   nothing to do about it
    # - dataset_in_pools: user_namespace_map_id -> user_namespace_id
    # - user_namespace_map_ugids -> user_namespace_ugids
    # - user_namespace_map_nodes -> user_namespace_nodes

    remove_column :dataset_in_pools, :user_namespace_map_id
    drop_table :user_namespace_map_nodes
    drop_table :user_namespace_map_ugids
    drop_table :user_namespace_map_entries
    drop_table :user_namespace_maps
  end
end
