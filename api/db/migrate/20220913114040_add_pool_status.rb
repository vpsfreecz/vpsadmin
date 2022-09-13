class AddPoolStatus < ActiveRecord::Migration[6.1]
  def change
    add_column :pools, :state, :integer, null: false, default: 0
    add_column :pools, :scan, :integer, null: false, default: 0
    add_column :pools, :checked_at, :datetime, null: true

    add_column :node_current_statuses, :pool_state, :integer, null: false, default: 0
    add_column :node_current_statuses, :pool_scan, :integer, null: false, default: 0
    add_column :node_current_statuses, :pool_checked_at, :datetime, null: true
  end
end
