class AddDnsServerZoneStatuses < ActiveRecord::Migration[7.1]
  def change
    add_column :dns_server_zones, :serial, :integer, unsigned: true, null: true
    add_column :dns_server_zones, :loaded_at, :datetime, null: true
    add_column :dns_server_zones, :expires_at, :datetime, null: true
    add_column :dns_server_zones, :refresh_at, :datetime, null: true
    add_column :dns_server_zones, :last_check_at, :datetime, null: true
  end
end
