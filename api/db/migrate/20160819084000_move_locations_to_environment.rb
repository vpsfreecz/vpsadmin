class MoveLocationsToEnvironment < ActiveRecord::Migration
  def change
    add_column :locations, :environment_id, :integer, null: false
    remove_column :servers, :environment_id, :integer, null: false
  end
end
