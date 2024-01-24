class AddAutoResolve < ActiveRecord::Migration[7.1]
  def change
    add_column :outages, :auto_resolve, :boolean, null: false, default: true
  end
end
