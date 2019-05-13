class AddUserFailedLogins < ActiveRecord::Migration
  def change
    create_table :user_failed_logins do |t|
      t.references  :user,               null: false
      t.string      :auth_type,          null: false, limit: 30
      t.string      :reason,             null: false, limit: 255
      t.string      :api_ip_addr,        null: true,  limit: 46
      t.string      :api_ip_ptr,         null: true,  limit: 255
      t.string      :client_ip_addr,     null: true,  limit: 46
      t.string      :client_ip_ptr,      null: true,  limit: 255
      t.references  :user_agent,         null: true
      t.string      :client_version,     null: true,  limit: 255
      t.datetime    :created_at,         null: false
    end

    add_index :user_failed_logins, :user_id
    add_index :user_failed_logins, :auth_type
    add_index :user_failed_logins, :user_agent_id
  end
end
