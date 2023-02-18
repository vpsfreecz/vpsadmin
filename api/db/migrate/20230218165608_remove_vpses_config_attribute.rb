class RemoveVpsesConfigAttribute < ActiveRecord::Migration[6.1]
  def change
    remove_column :vpses, :config, :text, null: false
  end
end
