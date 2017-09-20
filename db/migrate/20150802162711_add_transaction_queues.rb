class AddTransactionQueues < ActiveRecord::Migration
  def change
    add_column :transactions, :queue, :string, limit: 30, null: false,
               default: 'general'
  end
end
