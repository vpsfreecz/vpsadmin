class MountStateTracking < ActiveRecord::Migration
  def change
    add_column :mounts, :current_state, :integer, null: false
  end
end
