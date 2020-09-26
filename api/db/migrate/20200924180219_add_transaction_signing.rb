class AddTransactionSigning < ActiveRecord::Migration
  def change
    add_column :transactions, :signature, :text, null: true
  end
end
