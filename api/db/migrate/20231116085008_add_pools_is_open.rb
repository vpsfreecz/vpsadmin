class AddPoolsIsOpen < ActiveRecord::Migration[7.0]
  def change
    add_column :pools, :is_open, :integer, null: false, default: true
    add_index :pools, :is_open
  end
end
