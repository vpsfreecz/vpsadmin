class RefactorLocations < ActiveRecord::Migration
  def change
    rename_column :locations, :location_id, :id
    rename_column :locations, :location_label, :label
    rename_column :locations, :location_has_ipv6, :has_ipv6
    rename_column :locations, :location_vps_onboot, :vps_onboot
    rename_column :locations, :location_remote_console_server, :remote_console_server
  end
end
