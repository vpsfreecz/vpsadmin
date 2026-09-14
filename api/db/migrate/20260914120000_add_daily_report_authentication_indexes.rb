class AddDailyReportAuthenticationIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :user_sessions, :created_at
    add_index :user_sessions, :closed_at
    add_index :password_change_logs, :created_at
    add_index :user_failed_logins, :created_at
  end
end
