class AddNetworkInterfaceEnable < ActiveRecord::Migration[7.2]
  def change
    add_column :network_interfaces, :enable, :boolean, null: false, default: true
  end
end
