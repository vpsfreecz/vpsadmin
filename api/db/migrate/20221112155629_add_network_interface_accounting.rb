class AddNetworkInterfaceAccounting < ActiveRecord::Migration[6.1]
  def change
    create_table :network_interface_monitors do |t|
      t.references  :network_interface,       null: false, index: false
      t.bigint      :packets,                 null: false, unsigned: true
      t.bigint      :packets_in,              null: false, unsigned: true
      t.bigint      :packets_out,             null: false, unsigned: true
      t.bigint      :bytes,                   null: false, unsigned: true
      t.bigint      :bytes_in,                null: false, unsigned: true
      t.bigint      :bytes_out,               null: false, unsigned: true
      t.integer     :delta,                   null: false
      t.bigint      :packets_in_readout,      null: false, unsigned: true
      t.bigint      :packets_out_readout,     null: false, unsigned: true
      t.bigint      :bytes_in_readout,        null: false, unsigned: true
      t.bigint      :bytes_out_readout,       null: false, unsigned: true
      t.timestamps                            null: false
    end

    add_index :network_interface_monitors, :network_interface_id,
      name: 'index_network_interface_monitors_unique',
      unique: true

    create_table :network_interface_yearly_accountings do |t|
      t.references  :network_interface,       null: false, index: false
      t.bigint      :packets_in,              null: false, unsigned: true
      t.bigint      :packets_out,             null: false, unsigned: true
      t.bigint      :bytes_in,                null: false, unsigned: true
      t.bigint      :bytes_out,               null: false, unsigned: true
      t.integer     :year,                    null: false
      t.timestamps                            null: false
    end

    add_index :network_interface_yearly_accountings, :network_interface_id,
      name: 'index_network_interface_yearly_accountings_on_netif'

    add_index :network_interface_yearly_accountings,
      %i(network_interface_id year),
      name: 'index_network_interface_yearly_accountings_unique',
      unique: true

    create_table :network_interface_monthly_accountings do |t|
      t.references  :network_interface,       null: false, index: false
      t.bigint      :packets_in,              null: false, unsigned: true
      t.bigint      :packets_out,             null: false, unsigned: true
      t.bigint      :bytes_in,                null: false, unsigned: true
      t.bigint      :bytes_out,               null: false, unsigned: true
      t.integer     :year,                    null: false
      t.integer     :month,                   null: false
      t.timestamps                            null: false
    end

    add_index :network_interface_monthly_accountings, :network_interface_id,
      name: 'index_network_interface_monthly_accountings_on_netif'

    add_index :network_interface_monthly_accountings,
      %i(network_interface_id year month),
      name: 'index_network_interface_monthly_accountings_unique',
      unique: true

    create_table :network_interface_daily_accountings do |t|
      t.references  :network_interface,       null: false, index: false
      t.bigint      :packets_in,              null: false, unsigned: true
      t.bigint      :packets_out,             null: false, unsigned: true
      t.bigint      :bytes_in,                null: false, unsigned: true
      t.bigint      :bytes_out,               null: false, unsigned: true
      t.integer     :year,                    null: false
      t.integer     :month,                   null: false
      t.integer     :day,                     null: false
      t.timestamps                            null: false
    end

    add_index :network_interface_daily_accountings, :network_interface_id,
      name: 'index_network_interface_daily_accountings_on_netif'

    add_index :network_interface_daily_accountings,
      %i(network_interface_id year month day),
      name: 'index_network_interface_daily_accountings_unique',
      unique: true
  end
end
