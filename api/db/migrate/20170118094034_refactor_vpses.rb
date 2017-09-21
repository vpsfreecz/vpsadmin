class RefactorVpses < ActiveRecord::Migration
  def change
    rename_table :vps, :vpses
    rename_column :vpses, :vps_id, :id
    rename_column :vpses, :m_id, :user_id
    rename_column :vpses, :vps_hostname, :hostname
    rename_column :vpses, :vps_template, :os_template_id
    rename_column :vpses, :vps_info, :info
    rename_column :vpses, :vps_server, :node_id
    rename_column :vpses, :vps_onboot, :onboot
    rename_column :vpses, :vps_onstartall, :onstartall
    rename_column :vpses, :vps_config, :config

    rename_table :vps_console, :vps_consoles

    reversible do |dir|
      dir.up do
        remove_index :vpses, name: :m_id

        ActiveRecord::Base.connection.execute("
            UPDATE cluster_resource_uses
            SET table_name = 'vpses'
            WHERE table_name = 'vps'
        ")
      end

      dir.down do
        add_index :vpses, :user_id, name: :m_id

        ActiveRecord::Base.connection.execute("
            UPDATE cluster_resource_uses
            SET table_name = 'vps'
            WHERE table_name = 'vpses'
        ")
      end
    end

    add_index :vpses, :os_template_id
    add_index :vpses, :dns_resolver_id
    add_index :vpses, :object_state
    add_index :vpses, :dataset_in_pool_id
  end
end
