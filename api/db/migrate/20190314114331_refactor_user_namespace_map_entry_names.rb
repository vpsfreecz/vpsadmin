class RefactorUserNamespaceMapEntryNames < ActiveRecord::Migration
  def up
    rename_column :user_namespace_map_entries, :ns_id, :vps_id
    rename_column :user_namespace_map_entries, :host_id, :ns_id
  end

  def down
    rename_column :user_namespace_map_entries, :ns_id, :host_id
    rename_column :user_namespace_map_entries, :vps_id, :ns_id
  end
end
