class AddStatusLastLog < ActiveRecord::Migration[7.0]
  def change
    add_column :node_current_statuses, :last_log_at, :datetime, null: true
    add_column :vps_current_statuses, :last_log_at, :datetime, null: true
    add_column :dataset_properties, :last_log_at, :datetime, null: true
  end
end
