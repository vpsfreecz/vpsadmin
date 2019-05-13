class AddAuthTokenClientInfo < ActiveRecord::Migration
  def change
    add_column :auth_tokens, :api_ip_addr, :string, null: true, limit: 46
    add_column :auth_tokens, :api_ip_ptr, :string, null: true, limit: 255
    add_column :auth_tokens, :client_ip_addr, :string, null: true, limit: 46
    add_column :auth_tokens, :client_ip_ptr, :string, null: true, limit: 255
    add_column :auth_tokens, :user_agent_id, :integer, null: true
    add_column :auth_tokens, :client_version, :string, null: true, limit: 255
  end
end
