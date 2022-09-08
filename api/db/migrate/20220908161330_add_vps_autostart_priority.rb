class AddVpsAutostartPriority < ActiveRecord::Migration[6.1]
  def change
    add_column :vpses, :autostart_priority, :integer, null: false, default: 1000
  end
end
