class TransactionRollback < ActiveRecord::Migration
  def change
    add_column :transaction_chains, :urgent_rollback, :integer, null: false, default: false
    add_column :transactions, :reversible, :integer, null: false, default: true
  end
end
