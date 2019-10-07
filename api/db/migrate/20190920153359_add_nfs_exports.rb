class AddNfsExports < ActiveRecord::Migration
  def change
    create_table :exports do |t|
      t.references  :dataset_in_pool,               null: false
      t.references  :snapshot_in_pool_clone,        null: true
      t.references  :user,                          null: false
      t.boolean     :all_vps,                       null: false, default: true
      t.string      :path,                          null: false, limit: 255
      t.boolean     :rw,                            null: false, default: true
      t.boolean     :sync,                          null: false, default: true
      t.boolean     :subtree_check,                 null: false, default: false
      t.boolean     :root_squash,                   null: false, default: false
      t.boolean     :enabled,                       null: false, default: true
      t.integer     :object_state,                  null: false
      t.datetime    :expiration_date,               null: true
      t.integer     :confirmed,                     null: false, default: 0
      t.timestamps                                  null: false
    end

    add_index :exports, :dataset_in_pool_id, unique: true
    add_index :exports, :snapshot_in_pool_clone_id, unique: true
    add_index :exports, :user_id

    create_table :export_hosts do |t|
      t.references  :export,                        null: false
      t.references  :ip_address,                    null: false
      t.timestamps                                  null: false
    end

    add_index :export_hosts, %i(export_id ip_address_id), unique: true

    add_column :network_interfaces, :export_id, :integer, null: true
    change_column_null :network_interfaces, :vps_id, true
    add_index :network_interfaces, %i(export_id name), unique: true

    add_column :pools, :export_root, :string,
      null: false,
      limit: 100,
      default: '/export'
  end
end
