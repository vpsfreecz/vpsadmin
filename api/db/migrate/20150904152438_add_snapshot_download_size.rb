class AddSnapshotDownloadSize < ActiveRecord::Migration
  def change
    add_column :snapshot_downloads, :size, :integer, null: true
  end
end
