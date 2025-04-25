class AddExportsOriginalEnabled < ActiveRecord::Migration[7.2]
  def change
    add_column :exports, :original_enabled, :boolean, null: false, default: true
  end
end
