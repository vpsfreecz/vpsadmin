class AddShaper < ActiveRecord::Migration
  class IpAddress < ActiveRecord::Base
    self.table_name = 'vps_ip'
    self.primary_key = 'ip_id'
  end

  def change
    add_column :servers, :net_interface, :string, limit: 50, null: true
    add_column :servers, :max_tx, 'bigint unsigned', null: false, default: 235_929_600 # 1800 Mbps
    add_column :servers, :max_rx, 'bigint unsigned', null: false, default: 235_929_600 # 1800 Mbps

    add_column :vps_ip, :max_tx, 'bigint unsigned', null: false, default: 39_321_600 # 300 Mbps
    add_column :vps_ip, :max_rx, 'bigint unsigned', null: false, default: 39_321_600 # 300 Mbps
    add_column :vps_ip, :class_id, :integer, null: false

    reversible do |dir|
      dir.up do
        class_id = 10

        IpAddress.all.each do |ip|
          ip.update(class_id: class_id)

          class_id += 1
        end
      end
    end

    add_index :vps_ip, :class_id, unique: true
  end
end
