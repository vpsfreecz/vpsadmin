class AddVpsStartMenu < ActiveRecord::Migration[6.1]
  def change
    add_column :vpses, :start_menu_timeout, :integer, default: 5
  end
end
