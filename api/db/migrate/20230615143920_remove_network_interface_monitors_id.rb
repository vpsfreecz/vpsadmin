class RemoveNetworkInterfaceMonitorsId < ActiveRecord::Migration[7.0]
  def up
    remove_column :network_interface_monitors, :id
    remove_index :network_interface_monitors, :network_interface_id

    ActiveRecord::Base.connection.execute('ALTER TABLE network_interface_monitors ADD PRIMARY KEY(network_interface_id)')
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
