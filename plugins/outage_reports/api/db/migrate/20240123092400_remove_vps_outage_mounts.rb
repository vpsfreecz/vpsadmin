class RemoveVpsOutageMounts < ActiveRecord::Migration[7.1]
  def change
    remove_index :outage_vps_mounts, %i(outage_vps_id mount_id), unique: true

    drop_table :outage_vps_mounts do |t|
      t.references  :outage_vps,     null: false
      t.references  :mount,          null: false
      t.references  :src_node,       null: false
      t.references  :src_pool,       null: false
      t.references  :src_dataset,    null: false
      t.references  :src_snapshot,   null: true
      t.string      :dataset_name,   null: false, limit: 500
      t.string      :snapshot_name,  null: true,  limit: 255
      t.string      :mountpoint,     null: false, limit: 500
    end
  end
end
