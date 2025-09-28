require 'securerandom'

class AddLibvirt < ActiveRecord::Migration[7.2]
  class ConsolePort < ActiveRecord::Base; end

  class MacAddress < ActiveRecord::Base; end

  class NetworkInterface < ActiveRecord::Base
    belongs_to :guest_mac_address, class_name: 'MacAddress'
  end

  class Vps < ActiveRecord::Base
    belongs_to :uuid
  end

  class Uuid < ActiveRecord::Base; end

  def change
    create_table :uuids do |t|
      t.string      :uuid,            null: false, limit: 36
    end

    add_index :uuids, :uuid, unique: true

    create_table :storage_pools do |t|
      t.references  :uuid,            null: false, index: false
      t.references  :node,            null: false
      t.string      :name,            null: false, limit: 50
      t.string      :path,            null: false, limit: 500
      t.integer     :confirmed,       null: false, default: 0
      t.timestamps                    null: false
    end

    add_index :storage_pools, :uuid_id, unique: true

    create_table :storage_volumes do |t|
      t.references  :storage_pool,    null: false
      t.references  :user,            null: false
      t.references  :vps,             null: true
      t.string      :name,            null: false, limit: 50
      t.integer     :format,          null: false, default: 0
      t.integer     :size,            null: false
      t.string      :label,           null: false, limit: 50
      t.string      :filesystem,      null: false, limit: 10
      t.integer     :confirmed,       null: false, default: 0
      t.timestamps                    null: false
    end

    create_table :console_ports do |t|
      t.integer     :port,            null: false
      t.references  :vps,             null: true
    end

    add_index :console_ports, :port, unique: true

    reversible do |dir|
      dir.up do
        (10_000..10_100).each do |port|
          ConsolePort.create!(port:)
        end
      end
    end

    add_column :vpses, :vm_type, :integer, null: false, default: 0
    add_column :vpses, :uuid_id, :bigint, null: true
    add_column :vpses, :storage_volume_id, :bigint, null: true
    add_column :vpses, :console_port_id, :bigint, null: true

    add_index :vpses, :vm_type
    add_index :vpses, :uuid_id, unique: true
    add_index :vpses, :storage_volume_id
    add_index :vpses, :console_port_id, unique: true

    create_table :mac_addresses do |t|
      t.string :addr, null: false, limit: 17
      t.timestamps null: false
    end

    add_index :mac_addresses, :addr, unique: true

    add_column :network_interfaces, :host_mac_address_id, :bigint, null: true
    add_column :network_interfaces, :guest_mac_address_id, :bigint, null: true

    add_index :network_interfaces, :host_mac_address_id, unique: true
    add_index :network_interfaces, :guest_mac_address_id, unique: true

    reversible do |dir|
      dir.up do
        Vps.all.each do |vps|
          10.times do
            vps.update!(uuid: Uuid.create!(uuid: SecureRandom.uuid))
          rescue ActiveRecord::RecordNotUnique
            sleep(0.1)
            next
          else
            break
          end

          raise "Unable to generate uuid for VPS #{vps.id}" if vps.uuid.nil?
        end

        NetworkInterface.where.not(mac: nil).each do |netif|
          guest_mac = MacAddress.create!(
            addr: netif.mac,
            created_at: netif.created_at,
            updated_at: netif.updated_at
          )

          netif.update!(guest_mac_address_id: guest_mac.id)
        end
      end

      dir.down do
        NetworkInterface.where.not(guest_mac_address_id: nil).each do |netif|
          netif.update!(mac: netif.guest_mac_address.addr)
        end
      end
    end

    remove_index :network_interfaces, :mac, unique: true
    remove_column :network_interfaces, :mac, :string, null: true, limit: 17
  end
end
