class AddStorageVolumeStats < ActiveRecord::Migration[7.2]
  def change
    add_column :storage_volumes, :fs_used, :bigint, null: true
    add_column :storage_volumes, :fs_total, :bigint, null: true
  end
end
