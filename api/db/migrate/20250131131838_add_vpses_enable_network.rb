class AddVpsesEnableNetwork < ActiveRecord::Migration[7.2]
  def change
    add_column :vpses, :enable_network, :boolean, null: false, default: true
  end
end
