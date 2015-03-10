class AddTransactionChainConcerns < ActiveRecord::Migration
  def change
    add_column :transaction_chains, :concerns, :string, null: true, limit: 255
  end
end
