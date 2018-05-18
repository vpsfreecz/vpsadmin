class AddUsernsTimestamps < ActiveRecord::Migration
  def change
    add_timestamps(:user_namespaces, null: true)
    add_timestamps(:user_namespace_maps, null: true)
    add_timestamps(:user_namespace_map_entries, null: true)
  end
end
