class AddUserDevicesSkipMultiFactorAuthUntil < ActiveRecord::Migration[7.1]
  def change
    add_column :user_devices, :skip_multi_factor_auth_until, :datetime, null: true

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute('
          UPDATE user_devices
          SET skip_multi_factor_auth_until = DATE_ADD(updated_at, INTERVAL 1 MONTH)
          WHERE skip_multi_factor_auth = 1
        ')
      end
    end

    remove_column :user_devices, :skip_multi_factor_auth, :boolean, null: false, default: false
  end
end
