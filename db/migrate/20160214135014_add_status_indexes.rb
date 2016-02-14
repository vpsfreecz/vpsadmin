class AddStatusIndexes < ActiveRecord::Migration
  def change
    add_index :vps_statuses, :vps_id
    add_index :node_statuses, :node_id
  end
end
