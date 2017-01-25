class UserSessionsClientIpTracking < ActiveRecord::Migration
  def change
    rename_column :user_sessions, :ip_addr, :api_ip_addr
    add_column :user_sessions, :api_ip_ptr, :string, limit: 255, null: true
    add_column :user_sessions, :client_ip_addr, :string, limit: 46, null: true
    add_column :user_sessions, :client_ip_ptr, :string, limit: 255, null: true
  end
end
