class AddTransactionChainConcernsIndexes < ActiveRecord::Migration[6.1]
  def change
    add_index :transaction_chain_concerns, :class_name
    add_index :transaction_chain_concerns, :row_id
    add_index :transaction_chain_concerns, %i(class_name row_id)
  end
end
