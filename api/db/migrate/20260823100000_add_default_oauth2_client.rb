class AddDefaultOauth2Client < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth2_clients, :is_default, :boolean
    add_index :oauth2_clients, :is_default, unique: true
  end
end
