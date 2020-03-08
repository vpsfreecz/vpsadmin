class AddPoolMigrationPubkeys < ActiveRecord::Migration
  def change
    add_column :pools, :migration_public_key, :text, null: true
  end
end
