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
      t.references  :user,                    null: false, index: false
      t.bigint      :packets_in,              null: false, unsigned: true
      t.bigint      :packets_out,             null: false, unsigned: true
      t.bigint      :bytes_in,                null: false, unsigned: true
      t.bigint      :bytes_out,               null: false, unsigned: true
      t.integer     :year,                    null: false
      t.timestamps                            null: false
    end

    add_index :network_interface_yearly_accountings, :network_interface_id,
              name: 'index_network_interface_yearly_accountings_on_netif'

    add_index :network_interface_yearly_accountings, :user_id,
              name: 'index_network_interface_yearly_accountings_on_user_id'

    add_index :network_interface_yearly_accountings,
              %i[network_interface_id year],
              name: 'index_network_interface_yearly_accountings_unique',
              unique: true

    create_table :network_interface_monthly_accountings do |t|
      t.references  :network_interface,       null: false, index: false
      t.references  :user,                    null: false, index: false
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

    add_index :network_interface_monthly_accountings, :user_id,
              name: 'index_network_interface_monthly_accountings_on_user_id'

    add_index :network_interface_monthly_accountings,
              %i[network_interface_id year month],
              name: 'index_network_interface_monthly_accountings_unique',
              unique: true

    create_table :network_interface_daily_accountings do |t|
      t.references  :network_interface,       null: false, index: false
      t.references  :user,                    null: false, index: false
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

    add_index :network_interface_daily_accountings, :user_id,
              name: 'index_network_interface_daily_accountings_on_user_id'

    add_index :network_interface_daily_accountings,
              %i[network_interface_id year month day],
              name: 'index_network_interface_daily_accountings_unique',
              unique: true

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute('
          INSERT INTO network_interface_yearly_accountings
            (network_interface_id, user_id,
            packets_in, packets_out,
            bytes_in, bytes_out,
            `year`,
            created_at, updated_at)
          SELECT
            ips.network_interface_id, vpses.user_id,
            SUM(tr.packets_in), SUM(tr.packets_out),
            SUM(tr.bytes_in), SUM(tr.bytes_out),
            tr.`year`,
            tr.created_at, tr.created_at
          FROM ip_traffic_monthly_summaries tr
          INNER JOIN ip_addresses ips ON tr.ip_address_id = ips.id
          INNER JOIN network_interfaces netifs ON ips.network_interface_id = netifs.id
          INNER JOIN vpses ON netifs.vps_id = vpses.id
          GROUP BY ips.network_interface_id, tr.`year`
        ')

        ActiveRecord::Base.connection.execute('
          INSERT INTO network_interface_monthly_accountings
            (network_interface_id, user_id,
            packets_in, packets_out,
            bytes_in, bytes_out,
            `year`, `month`,
            created_at, updated_at)
          SELECT
            ips.network_interface_id, vpses.user_id,
            SUM(tr.packets_in), SUM(tr.packets_out),
            SUM(tr.bytes_in), SUM(tr.bytes_out),
            tr.`year`, tr.`month`,
            tr.created_at, tr.created_at
          FROM ip_traffic_monthly_summaries tr
          INNER JOIN ip_addresses ips ON tr.ip_address_id = ips.id
          INNER JOIN network_interfaces netifs ON ips.network_interface_id = netifs.id
          INNER JOIN vpses ON netifs.vps_id = vpses.id
          GROUP BY ips.network_interface_id, tr.`year`, tr.`month`
        ')
      end
    end
  end
end
