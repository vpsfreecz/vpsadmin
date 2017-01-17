class RefactorIpAddresses < ActiveRecord::Migration
  def change
    rename_table :vps_ip, :ip_addresses
    rename_column :ip_addresses, :ip_id, :id
  end
end
