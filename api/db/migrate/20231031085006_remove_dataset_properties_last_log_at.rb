class RemoveDatasetPropertiesLastLogAt < ActiveRecord::Migration[7.0]
  def change
    remove_column :dataset_properties, :last_log_at, :datetime, null: true
  end
end
