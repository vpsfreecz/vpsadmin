class AddSmsNotificationsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :sms_notifications_enabled, :boolean, null: false, default: false
  end
end
