class AdminUserSession < ActiveRecord::Migration
  def change
    add_column :user_sessions, :admin_id, :integer, null: true
  end
end
