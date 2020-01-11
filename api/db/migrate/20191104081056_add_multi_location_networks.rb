class AddMultiLocationNetworks < ActiveRecord::Migration
  class Network < ActiveRecord::Base ; end
  class Location < ActiveRecord::Base ; end
  class LocationNetwork < ActiveRecord::Base ; end
  class IpAddress < ActiveRecord::Base ; end

  def change
    create_table :location_networks do |t|
      t.references  :location,                 null: false
      t.references  :network,                  null: false
      t.integer     :priority,                 null: false, default: 10
      t.boolean     :autopick,                 null: false, default: true
      t.boolean     :userpick,                 null: false, default: true
    end

    add_index :location_networks, %i(location_id network_id), unique: true

    add_column :ip_addresses, :charged_environment_id, :integer, null: true
    add_index :ip_addresses, :charged_environment_id

    reversible do |dir|
      dir.up do
        Network.all.each do |net|
          LocationNetwork.create!(
            location_id: net.location_id,
            network_id: net.id,
            autopick: net.autopick,
            userpick: net.autopick,
          )
        end

        IpAddress.where.not(network_interface_id: nil).each do |ip|
          net = Network.find(ip.network_id)
          loc = Location.find(net.location_id)

          ip.update!(
            charged_environment_id: loc.environment_id,
          )
        end
      end

      dir.down do
        Network.all.each do |net|
          locnet = LocationNetwork.where(
            network_id: net.id,
          ).order('priority, id').take

          if locnet.nil?
            warn "No location found for network #{net.address}/#{net.prefix}"
            next
          end

          net.update!(
            location_id: locnet.location_id,
            autopick: locnet.autopick,
          )
        end
      end
    end

    remove_index :networks, column: %i(location_id address prefix), unique: true
    remove_column :networks, :autopick, :boolean, null: false, default: true
    remove_column :networks, :location_id, :integer, null: false
    add_index :networks, %i(address prefix), unique: true
  end
end
