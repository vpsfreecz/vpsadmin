class TransactionConfirmationsAttrChangesText < ActiveRecord::Migration
  def up
    change_column :transaction_confirmations, :attr_changes, :text, null: true
  end

  def down
    change_column :transaction_confirmations, :attr_changes, :string, null: true,
                  limit: 255
  end
end
