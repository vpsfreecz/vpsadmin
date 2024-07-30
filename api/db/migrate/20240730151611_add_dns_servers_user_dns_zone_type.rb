class AddDnsServersUserDnsZoneType < ActiveRecord::Migration[7.1]
  def change
    add_column :dns_servers, :user_dns_zone_type, :integer, null: false, default: 0
  end
end
