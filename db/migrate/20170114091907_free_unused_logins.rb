class FreeUnusedLogins < ActiveRecord::Migration
  def change
    add_column :members, :orig_login, :string, null: true, limit: 63

    reversible do |dir|
      dir.up do
        change_column_null :members, :m_nick, true
        
        ActiveRecord::Base.connection.execute('
            UPDATE members
            SET orig_login = m_nick, m_nick = NULL
            WHERE object_state = 3
        ')
      end

      dir.down do
        change_column_null :members, :m_nick, false
      end
    end
  end
end
