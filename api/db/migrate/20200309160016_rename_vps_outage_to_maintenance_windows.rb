class RenameVpsOutageToMaintenanceWindows < ActiveRecord::Migration
  def change
    rename_table :vps_outage_windows, :vps_maintenance_windows
  end
end
