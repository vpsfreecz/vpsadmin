class AddUserSessions < ActiveRecord::Migration
  def change
    create_table :user_session_agents do |t|
      t.text        :agent,              null: false, limit: 65535
      t.string      :agent_hash,         null: false, limit: 40
      t.datetime    :created_at,         null: false
    end

    add_index :user_session_agents, :agent_hash, unique: true,
              name: :user_session_agents_hash

    create_table :user_sessions do |t|
      t.references  :user,               null: false
      t.string      :auth_type,          null: false, limit: 30
      t.string      :ip_addr,            null: false, limit: 46
      t.references  :user_session_agent, null: true
      t.string      :client_version,     null: false, limit: 255
      t.references  :api_token,          null: true
      t.string      :api_token_str,      null: true,  limit: 100
      t.datetime    :created_at,         null: false
      t.datetime    :last_request_at,    null: true
      t.datetime    :closed_at,          null: true
    end

    add_column :transaction_chains, :user_session_id, :integer, null: true
  end
end
