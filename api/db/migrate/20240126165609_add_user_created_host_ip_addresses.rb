class AddUserCreatedHostIpAddresses < ActiveRecord::Migration[7.1]
  def change
    add_column :host_ip_addresses, :user_created, :boolean, null: false, default: false
  end
end
