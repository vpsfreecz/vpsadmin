class RemoveNodeVzAttrs < ActiveRecord::Migration[6.1]
  def change
    remove_column :nodes, :ve_private, :string, null: true, limit: 255, default: '/vz/private/%{veid}/private'
    remove_column :nodes, :net_interface, :string, null: true, limit: 50
  end
end
