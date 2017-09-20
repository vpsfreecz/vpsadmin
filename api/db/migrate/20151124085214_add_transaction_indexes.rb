class AddTransactionIndexes < ActiveRecord::Migration
  def change
    add_index :transactions, :t_done
    add_index :transaction_chains, :state
  end
end
