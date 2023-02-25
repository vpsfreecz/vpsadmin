class RenameNodeStatusesVpsadmindVersion < ActiveRecord::Migration[6.1]
  def change
    rename_column :node_current_statuses, :vpsadmind_version, :vpsadmin_version
    rename_column :node_statuses, :vpsadmind_version, :vpsadmin_version
  end
end
