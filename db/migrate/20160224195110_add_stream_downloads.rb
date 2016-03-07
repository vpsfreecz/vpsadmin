class AddStreamDownloads < ActiveRecord::Migration
  def change
    add_column :snapshot_downloads, :format, :integer, null: false, default: 0
    add_column :snapshot_downloads, :from_snapshot_id, :integer, null: true
  end
end
