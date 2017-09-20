class AddTransactionChainConcerns < ActiveRecord::Migration
  def change
    add_column :transaction_chains, :concern_type, :integer, null: false, default: 0

    create_table :transaction_chain_concerns do |t|
      t.references :transaction_chain, null: false
      t.string     :class_name,        null: false, limit: 255
      t.integer    :row_id,            null: false
    end
  end
end
