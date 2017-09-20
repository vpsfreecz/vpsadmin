class UserOwnsIpAddresses < ActiveRecord::Migration
  def change
    add_column :vps_ip, :user_id, :integer, null: true
    add_column :environments, :user_ip_ownership, :boolean, null: false
  end
end
