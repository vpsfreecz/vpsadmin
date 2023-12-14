class AddOauth2ClientSettings < ActiveRecord::Migration[7.0]
  def change
    add_column :oauth2_clients, :access_token_lifetime, :integer, null: false, default: 0
    add_column :oauth2_clients, :access_token_seconds, :integer, null: false, default: 15*60
    add_column :oauth2_clients, :refresh_token_seconds, :integer, null: false, default: 60*60
    add_column :oauth2_clients, :issue_refresh_token, :boolean, null: false, default: false
  end
end
