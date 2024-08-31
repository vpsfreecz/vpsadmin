class AddUsersEnableNewLoginNotification < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :enable_new_login_notification, :boolean, null: false, default: true
  end
end
