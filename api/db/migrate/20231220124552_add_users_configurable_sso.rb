class AddUsersConfigurableSso < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :enable_single_sign_on, :boolean, default: true
  end
end
