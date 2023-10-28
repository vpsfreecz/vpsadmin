class AddNetworkInterfaceAccountingIndexes < ActiveRecord::Migration[7.0]
  def change
    add_index :network_interface_daily_accountings, :year,
      name: 'index_network_interface_daily_accountings_on_year'
    add_index :network_interface_daily_accountings, :month,
      name: 'index_network_interface_daily_accountings_on_month'
    add_index :network_interface_daily_accountings, :day,
      name: 'index_network_interface_daily_accountings_on_day'

    add_index :network_interface_monthly_accountings, :year,
      name: 'index_network_interface_monthly_accountings_on_year'
    add_index :network_interface_monthly_accountings, :month,
      name: 'index_network_interface_monthly_accountings_on_month'

    add_index :network_interface_yearly_accountings, :year,
      name: 'index_network_interface_yearly_accountings_on_year'
  end
end
