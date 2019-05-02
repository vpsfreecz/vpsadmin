class AddUserPasswordReset < ActiveRecord::Migration
  def change
    add_column :users, :password_reset, :bool, null: false, default: false
    add_column :users, :lockout, :bool, null: false, default: false
  end
end
