class AddVpsVethMac < ActiveRecord::Migration
  def change
    add_column :vpses, :veth_mac, :string, limit: 17, null: true
    add_index :vpses, :veth_mac, unique: true
  end
end
