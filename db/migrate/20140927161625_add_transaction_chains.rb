class AddTransactionChains < ActiveRecord::Migration
  def change
    create_table :transaction_chains do |t|
      t.string     :name,           null: false, limit: 30
      t.string     :type,           null: false, limit: 100
      t.integer    :state,          null: false
      t.integer    :size,           null: false
      t.integer    :progress,       null: false, default: 0
      t.references :user,           null: true
      t.timestamps
    end

    add_column :transactions, :transaction_chain_id, :integer, null: false

    create_table :transaction_confirmations do |t|
      t.references :transaction,    null: false
      t.string     :class_name,     null: false, limit: 255
      t.string     :table_name,     null: false, limit: 255
      t.string     :row_pks,        null: false
      t.string     :attr_changes,   null: true

      # enum
      #  0 - create (success - confirm, failure - destroy)
      #  1 - edit before (success - ignore, failure - revert)
      #  2 - edit after (success - edit, failure - ignore)
      #  3 - destroy (success - destroy, failure - revert to confirm)
      t.integer    :confirm_type,   null: false
      t.integer    :done,           null: false, default: 0
      t.timestamps
    end

    create_table :resource_locks do |t|
      t.string     :resource,       null: false, limit: 100
      t.integer    :row_id,         null: false
      t.references :transaction_chain, null: true
      t.timestamps
    end

    add_index :resource_locks, [:resource, :row_id], unique: true

    remove_column :vps, :vps_backup_lock, :boolean, null: false, default: false

    add_column :vps, :confirmed, :boolean, null: false, default: false
    add_column :vps_has_config, :confirmed, :boolean, null: false, default: false

    reversible do |dir|
      dir.up do
        Transaction.connection.execute('ALTER TABLE transactions ENGINE = innodb')
      end

      dir.down do
        Transaction.connection.execute('ALTER TABLE transactions ENGINE = myisam')
      end
    end
  end
end
