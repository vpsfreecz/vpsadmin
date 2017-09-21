class RefactorTransactions < ActiveRecord::Migration
  def change
    reversible do |dir|
      dir.down do
        add_index :transactions, :t_server, name: :t_server

        remove_index :transactions, name: :index_transactions_on_t_m_id
        remove_index :transactions, name: :index_transactions_on_t_server
      end
    end

    rename_column :transactions, :t_id, :id
    rename_column :transactions, :t_m_id, :user_id
    rename_column :transactions, :t_server, :node_id
    rename_column :transactions, :t_vps, :vps_id
    rename_column :transactions, :t_type, :handle
    rename_column :transactions, :t_depends_on, :depends_on_id
    rename_column :transactions, :t_urgent, :urgent
    rename_column :transactions, :t_priority, :priority
    rename_column :transactions, :t_success, :status
    rename_column :transactions, :t_done, :done
    rename_column :transactions, :t_param, :input
    rename_column :transactions, :t_output, :output

    remove_column :transactions, :t_group, :integer, unsigned: true
    remove_column :transactions, :t_fallback, :text

    reversible do |dir|
      dir.up do
        remove_index :transactions, name: :t_server

        add_index :transactions, :node_id
        add_index :transactions, :user_id

        drop_table :transaction_groups
      end

      dir.down do
        create_table :transaction_groups do |t|
          t.boolean :is_clusterwide,  default: false, unsigned: true
          t.boolean :is_locationwide, default: false, unsigned: true
          t.integer :location_id,     default: 0,     unsigned: true
        end
      end
    end
  end
end
