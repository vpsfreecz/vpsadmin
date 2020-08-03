class AddLocationNetworkPrimary < ActiveRecord::Migration
  def change
    add_column :location_networks, :primary, :boolean, null: true
    add_index :location_networks, %i(network_id primary),
      unique: true,
      name: 'location_networks_primary'
    add_column :networks, :primary_location_id, :integer, null: true
  end
end
