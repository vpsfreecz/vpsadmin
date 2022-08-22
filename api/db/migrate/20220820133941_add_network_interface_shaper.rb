class AddNetworkInterfaceShaper < ActiveRecord::Migration[6.1]
  def change
    add_column :network_interfaces, :max_tx, 'bigint unsigned', null: false, default: 0
    add_column :network_interfaces, :max_rx, 'bigint unsigned', null: false, default: 0
  end
end
