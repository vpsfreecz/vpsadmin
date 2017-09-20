class AddMountOnStartFail < ActiveRecord::Migration
  def change
    add_column :mounts, :on_start_fail, :integer, null: false, default: 1
  end
end
