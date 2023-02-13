class RemoveUserNamespaceMapUgids < ActiveRecord::Migration[6.1]
  def up
    remove_column :user_namespace_maps, :user_namespace_map_ugid_id, :integer, null: false
    drop_table :user_namespace_map_ugids
  end

  def down
    create_table :user_namespace_map_ugids do |t|
      t.references :user_namespace_map,  null: true, unique: true
      t.integer    :ugid,                null: false, unsigned: true
    end

    add_index :user_namespace_map_ugids, :ugid, unique: true

    add_column :user_namespace_maps, :user_namespace_map_ugid_id, :integer, null: false, unique: true
  end
end
