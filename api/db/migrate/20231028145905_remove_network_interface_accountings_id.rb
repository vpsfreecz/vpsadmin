class RemoveNetworkInterfaceAccountingsId < ActiveRecord::Migration[7.0]
  def up
    # Daily
    remove_column :network_interface_daily_accountings, :id

    ActiveRecord::Base.connection.execute(
      'ALTER TABLE network_interface_daily_accountings ADD PRIMARY KEY(`network_interface_id`, `user_id`, `year`, `month`, `day`)'
    )

    remove_index :network_interface_daily_accountings,
                 %i[network_interface_id year month day],
                 name: 'index_network_interface_daily_accountings_unique'

    # Monthly
    remove_column :network_interface_monthly_accountings, :id

    ActiveRecord::Base.connection.execute(
      'ALTER TABLE network_interface_monthly_accountings ADD PRIMARY KEY(`network_interface_id`, `user_id`, `year`, `month`)'
    )

    remove_index :network_interface_monthly_accountings,
                 %i[network_interface_id year month],
                 name: 'index_network_interface_monthly_accountings_unique'

    # Yearly
    remove_column :network_interface_yearly_accountings, :id

    ActiveRecord::Base.connection.execute(
      'ALTER TABLE network_interface_yearly_accountings ADD PRIMARY KEY(`network_interface_id`, `user_id`, `year`)'
    )

    remove_index :network_interface_yearly_accountings,
                 %i[network_interface_id year],
                 name: 'index_network_interface_yearly_accountings_unique'
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
