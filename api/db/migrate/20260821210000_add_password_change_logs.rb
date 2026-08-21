class AddPasswordChangeLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :password_change_logs do |t|
      t.integer :user_id, unsigned: true, null: false
      t.integer :user_session_id, unsigned: true
      t.string :source, limit: 32, null: false
      t.datetime :created_at, null: false
    end

    add_index :password_change_logs,
              %i[user_id id],
              name: 'password_change_logs_user'
    add_index :password_change_logs,
              %i[user_id source id],
              name: 'password_change_logs_user_source'
    add_index :password_change_logs, :user_session_id
  end
end
