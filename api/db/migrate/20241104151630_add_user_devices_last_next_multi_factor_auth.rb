class AddUserDevicesLastNextMultiFactorAuth < ActiveRecord::Migration[7.1]
  def change
    add_column :user_devices, :last_next_multi_factor_auth, :string, null: false, limit: 30, default: ''
  end
end
