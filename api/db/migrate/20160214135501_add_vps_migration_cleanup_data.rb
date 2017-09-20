class AddVpsMigrationCleanupData < ActiveRecord::Migration
  def change
    add_column :vps_migrations, :cleanup_data, :boolean, default: true
  end
end
