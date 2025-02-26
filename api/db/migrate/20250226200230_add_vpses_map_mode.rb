class AddVpsesMapMode < ActiveRecord::Migration[7.2]
  def change
    add_column :vpses, :map_mode, :integer, null: false, default: 0

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute('UPDATE vpses SET map_mode = 1')
      end
    end

    add_index :vpses, :map_mode
  end
end
