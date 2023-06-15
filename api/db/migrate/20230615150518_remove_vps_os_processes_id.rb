class RemoveVpsOsProcessesId < ActiveRecord::Migration[7.0]
  def up
    remove_column :vps_os_processes, :id
    remove_index :vps_os_processes, %i(vps_id state)

    ActiveRecord::Base.connection.execute('ALTER TABLE vps_os_processes ADD PRIMARY KEY(`vps_id`, `state`)')
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
