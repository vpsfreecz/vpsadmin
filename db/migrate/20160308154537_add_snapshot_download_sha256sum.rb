class AddSnapshotDownloadSha256sum < ActiveRecord::Migration
  def change
    add_column :snapshot_downloads, :sha256sum, :string, limit: 64, null: true
  end
end
