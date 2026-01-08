class AddRemoteVncServerToLocations < ActiveRecord::Migration[8.1]
  def change
    add_column :locations, :remote_vnc_server, :string, limit: 255, null: false, default: ''
  end
end
