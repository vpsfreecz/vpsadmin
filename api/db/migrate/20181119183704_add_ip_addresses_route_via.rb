class AddIpAddressesRouteVia < ActiveRecord::Migration
  def change
    add_column :ip_addresses, :route_via_id, :integer, null: true
    add_index :ip_addresses, :route_via_id
  end
end
