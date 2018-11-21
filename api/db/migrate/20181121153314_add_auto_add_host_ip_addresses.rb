class AddAutoAddHostIpAddresses < ActiveRecord::Migration
  def change
    add_column :host_ip_addresses, :auto_add, :boolean, null: false, default: true
    add_index :host_ip_addresses, :auto_add
  end
end
