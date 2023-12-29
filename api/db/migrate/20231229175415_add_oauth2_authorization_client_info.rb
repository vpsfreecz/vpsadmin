class AddOauth2AuthorizationClientInfo < ActiveRecord::Migration[7.0]
  def change
    add_column :oauth2_authorizations, :client_ip_addr, :string, limit: 46, null: true
    add_column :oauth2_authorizations, :client_ip_ptr, :string, limit: 255, null: true
    add_column :oauth2_authorizations, :user_agent_id, :integer, null: true

    add_index :oauth2_authorizations, :user_agent_id
  end
end
