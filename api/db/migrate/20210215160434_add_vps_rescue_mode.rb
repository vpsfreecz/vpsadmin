class AddVpsRescueMode < ActiveRecord::Migration
  def change
    add_column :vps_current_statuses, :in_rescue_mode, :bool, default: false
    add_column :vps_statuses, :in_rescue_mode, :bool, default: false
  end
end
