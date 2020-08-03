class AddNodeActive < ActiveRecord::Migration
  def change
    add_column :nodes, :active, :boolean, null: false, default: true
    add_index :nodes, :active
  end
end
