class RemoveMountScripts < ActiveRecord::Migration
  def change
    remove_column :mounts, :cmd_premount, :string, limit: 500, null: true
    remove_column :mounts, :cmd_postmount, :string, limit: 500, null: true
    remove_column :mounts, :cmd_preumount, :string, limit: 500, null: true
    remove_column :mounts, :cmd_postumount, :string, limit: 500, null: true
  end
end
