class RemoveOldVpsBackups < ActiveRecord::Migration
  def up
    drop_table :vps_backups
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
