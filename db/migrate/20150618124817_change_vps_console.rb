class ChangeVpsConsole < ActiveRecord::Migration
  class VpsConsole < ActiveRecord::Base
    self.table_name = 'vps_console'
  end

  def change
    rename_column :vps_console, :key, :token

    reversible do |dir|
      dir.up do
        change_column :vps_console, :token, :string, limit: 100, null: true
        VpsConsole.update_all(token: nil)
      end

      dir.down do
        VpsConsole.where(token: nil).update_all(token: '!')
        change_column :vps_console, :token, :string, limit: 64, null: false
      end
    end

    add_column :vps_console, :user_id, :integer, null: true
    add_timestamps :vps_console
    add_index :vps_console, :token, unique: true
  end
end
