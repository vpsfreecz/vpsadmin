class AddSpaceToPools < ActiveRecord::Migration[8.1]
  def change
    add_column :pools, :total_space, :bigint, null: true
    add_column :pools, :used_space, :bigint, null: true
    add_column :pools, :available_space, :bigint, null: true
  end
end
