class AddMountToggle < ActiveRecord::Migration
  def change
    add_column :mounts, :enabled, :boolean, null: false, default: true
    add_column :mounts, :master_enabled, :boolean, null: false, default: true
  end
end
