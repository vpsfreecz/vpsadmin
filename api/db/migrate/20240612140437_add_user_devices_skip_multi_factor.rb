class AddUserDevicesSkipMultiFactor < ActiveRecord::Migration[7.1]
  class User < ActiveRecord::Base; end

  def change
    add_column :user_devices, :skip_multi_factor, :boolean, null: false, default: false
  end
end
