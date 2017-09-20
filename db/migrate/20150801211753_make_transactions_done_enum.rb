class MakeTransactionsDoneEnum < ActiveRecord::Migration
  def up
    change_column :transactions, :t_done, :integer, null: false, default: 0
  end

  def down
    change_column :transactions, :t_done, :boolean, null: false
  end
end
