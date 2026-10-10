class AddNetworkEnabled < ActiveRecord::Migration[8.1]
  def change
    add_column :networks, :enabled, :boolean, null: false, default: true
  end
end
