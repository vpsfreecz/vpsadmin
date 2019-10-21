class AddNetworkPurpose < ActiveRecord::Migration
  def change
    add_column :networks, :purpose, :integer, null: false, default: 0
    add_index :networks, :purpose
  end
end
