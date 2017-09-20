class MaintenanceMode < ActiveRecord::Migration
  def change
    remove_column :servers,   :server_maintenance, :boolean, default: false

    create_table :maintenance_locks do |t|
      t.string       :class_name,     null: false, limit: 100
      t.integer      :row_id,         null: true
      t.references   :user,           null: true
      t.string       :reason,         null: false, limit: 255
      t.boolean      :active,         null: false, default: true
      t.timestamps
    end

    add_index :maintenance_locks, %i(class_name row_id)

    add_column :environments, :maintenance_lock, :integer, null: false, default: 0
    add_column :environments, :maintenance_lock_reason, :string, null: true, limit: 255

    add_column :locations,    :maintenance_lock, :integer, null: false, default: 0
    add_column :locations,    :maintenance_lock_reason, :string, null: true, limit: 255

    add_column :servers,      :maintenance_lock, :integer, null: false, default: 0
    add_column :servers,      :maintenance_lock_reason, :string, null: true, limit: 255

    add_column :vps,          :maintenance_lock, :integer, null: false, default: 0
    add_column :vps,          :maintenance_lock_reason, :string, null: true, limit: 255
  end
end
