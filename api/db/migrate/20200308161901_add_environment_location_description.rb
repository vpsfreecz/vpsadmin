class AddEnvironmentLocationDescription < ActiveRecord::Migration
  def change
    add_column :environments, :description, :text, null: true
    add_column :locations, :description, :text, null: true
  end
end
