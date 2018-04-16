class AddNetworksAutopick < ActiveRecord::Migration
  def change
    add_column :networks, :autopick, :integer, null: false, default: true
  end
end
