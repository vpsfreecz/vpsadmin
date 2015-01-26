class AddSnapshotDownloads < ActiveRecord::Migration
  def change
    create_table :snapshot_downloads do |t|
      t.references   :snapshot,      null: false
      t.references   :pool,          null: false
      t.string       :secret_key,    null: false, limit: 100
      t.string       :file_name,     null: false, limit: 255
      t.integer      :confirmed,     null: false, default: 0
      t.timestamps
    end

    add_index :snapshot_downloads, :secret_key, unique: true

    add_column :snapshots, :snapshot_download_id, :integer, null: true
  end
end
