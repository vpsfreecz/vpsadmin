class AddPoolMaxDatasets < ActiveRecord::Migration[6.1]
  def change
    add_column :pools, :max_datasets, :integer, null: false, default: 0
  end
end
