class AddAccessToken < ActiveRecord::Migration
  def change
    add_column :user_requests, :access_token, :string, null: true, limit: 40
  end
end
