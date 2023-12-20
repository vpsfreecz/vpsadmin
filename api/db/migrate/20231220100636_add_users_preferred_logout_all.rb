class AddUsersPreferredLogoutAll < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :preferred_logout_all, :boolean, null: false, default: false
  end
end
