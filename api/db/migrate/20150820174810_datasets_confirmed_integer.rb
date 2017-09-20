class DatasetsConfirmedInteger < ActiveRecord::Migration
  def up
    change_column :datasets, :confirmed, :integer, null: false, default: 0
  end

  def down
    change_column :datasets, :confirmed, :boolean, null: false, default: false
  end
end
