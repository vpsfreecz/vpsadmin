class AddStreamDownloads < ActiveRecord::Migration
  def change
    add_column :snapshot_downloads, :format, :integer, null: false, default: 0
  end
end
