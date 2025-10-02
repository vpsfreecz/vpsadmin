class AddExportMounts < ActiveRecord::Migration[7.2]
  def change
    create_table :export_mounts do |t|
      t.references  :export,                 null: false
      t.references  :vps,                    null: false
      t.string      :mountpoint,             null: false, limit: 500
      t.string      :nfs_version,            null: false, limit: 10
      t.timestamps                           null: false
    end
  end
end
