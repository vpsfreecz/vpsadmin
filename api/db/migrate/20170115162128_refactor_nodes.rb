class RefactorNodes < ActiveRecord::Migration
  def change
    rename_table :servers, :nodes
    rename_column :nodes, :server_id, :id
    rename_column :nodes, :server_name, :name
    rename_column :nodes, :server_location, :location_id
    rename_column :nodes, :server_ip4, :ip_addr

    remove_column :nodes, :server_availstat, :text
    remove_column :nodes, :fstype, :string, limit: 10, default: 'zfs', null: false

    reversible do |dir|
      dir.up do
        remove_index :nodes, name: :server_location
        add_index :nodes, :location_id, name: :location_id

        add_column :nodes, :role, :integer, null: true
        ActiveRecord::Base.connection.execute("
            UPDATE nodes
            SET role = (
              CASE server_type
              WHEN 'node' THEN 0
              WHEN 'storage' THEN 1
              WHEN 'mailer' THEN 2
              END
            )
        ")

        remove_column :nodes, :server_type
        change_column_null :nodes, :role, false
      end

      dir.down do
        remove_index :nodes, name: :location_id
        add_index :nodes, :server_location, name: :server_location

        add_column :nodes, :server_type, :string, limit: 30, null: true
        ActiveRecord::Base.connection.execute("
            UPDATE nodes
            SET server_type = (
              CASE role
              WHEN 0 THEN 'node'
              WHEN 1 THEN 'storage'
              WHEN 2 THEN 'mailer'
              END
            )
        ")

        remove_column :nodes, :role
        change_column_null :nodes, :server_type, false
      end
    end
  end
end
