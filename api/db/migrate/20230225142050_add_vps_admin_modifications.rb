class AddVpsAdminModifications < ActiveRecord::Migration[6.1]
  def change
    add_column :vpses, :allow_admin_modifications, :boolean, null: false, default: true
    add_index :vpses, :allow_admin_modifications
  end
end
