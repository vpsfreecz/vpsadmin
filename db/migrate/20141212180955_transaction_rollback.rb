class TransactionRollback < ActiveRecord::Migration
  def change
    add_column :transactions, :reversible, :integer, null: false, default: true
  end
end
