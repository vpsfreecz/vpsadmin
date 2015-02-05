class UserOwnsIpAddresses < ActiveRecord::Migration
  def change
    add_column :vps_ip, :user_id, :integer, null: true
  end
end
