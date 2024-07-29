class AddDnsServerZoneSecondaries < ActiveRecord::Migration[7.1]
  def change
    add_column :dns_server_zones, :zone_type, :integer, null: false, default: 0
  end
end
