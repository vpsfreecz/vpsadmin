class AddMoreIndexes < ActiveRecord::Migration
  def change
    add_index :transactions, :t_success
    add_index :dataset_properties, :pool_id
    add_index :dataset_properties, :dataset_in_pool_id
    add_index :dataset_properties, %i(dataset_in_pool_id name)
  end
end
