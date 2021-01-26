class FixNfsExportUniqueIndexes < ActiveRecord::Migration
  def up
    add_column :exports, :snapshot_in_pool_clone_n, :integer, null: false, default: 0

    add_index :exports, %i(dataset_in_pool_id snapshot_in_pool_clone_n),
      name: :exports_unique,
      unique: true

    remove_index :exports, :dataset_in_pool_id
    remove_index :exports, :snapshot_in_pool_clone_id
  end

  def down
    remove_index :exports, name: :exports_unique
    remove_column :exports, :snapshot_in_pool_clone_n
    add_index :exports, :dataset_in_pool_id, unique: true
    add_index :exports, :snapshot_in_pool_clone_id, unique: true
  end
end
