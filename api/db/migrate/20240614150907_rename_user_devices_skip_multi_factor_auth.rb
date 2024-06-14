class RenameUserDevicesSkipMultiFactorAuth < ActiveRecord::Migration[7.1]
  def change
    rename_column :user_devices, :skip_multi_factor, :skip_multi_factor_auth
  end
end
