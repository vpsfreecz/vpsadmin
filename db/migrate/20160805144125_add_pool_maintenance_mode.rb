class AddPoolMaintenanceMode < ActiveRecord::Migration
  def change
    add_column :pools, :maintenance_lock, :integer, null: false, default: 0
    add_column :pools, :maintenance_lock_reason, :string, null: true, limit: 255
  end
end
