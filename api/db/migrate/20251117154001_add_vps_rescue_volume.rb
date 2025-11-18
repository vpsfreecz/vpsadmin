class AddVpsRescueVolume < ActiveRecord::Migration[7.2]
  def change
    add_column :vpses, :rescue_volume_id, :bigint, null: true
    add_index :vpses, :rescue_volume_id
  end
end
