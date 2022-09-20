class AddPoolScanPercent < ActiveRecord::Migration[6.1]
  def change
    add_column :pools, :scan_percent, :float, null: true
    add_column :node_current_statuses, :pool_scan_percent, :float, null: true
  end
end
