class AddWebauthn < ActiveRecord::Migration[7.2]
  def change
    create_table :webauthn_credentials do |t|
      t.references  :user,                null: false
      t.string      :label,               null: false, limit: 255
      t.string      :external_id,         null: false
      t.string      :public_key,          null: false
      t.bigint      :sign_count,          null: false, default: 0
      t.boolean     :enabled,             null: false, default: true
      t.datetime    :last_use_at,         null: true
      t.timestamps                        null: false
    end

    add_index :webauthn_credentials, :external_id, unique: true

    create_table :webauthn_challenges do |t|
      t.references  :user,                null: false
      t.references  :token,               null: false
      t.integer     :challenge_type,      null: false
      t.string      :challenge,           null: false
      t.string      :api_ip_addr,         null: false, limit: 46
      t.string      :api_ip_ptr,          null: false, limit: 255
      t.string      :client_ip_addr,      null: false, limit: 46
      t.string      :client_ip_ptr,       null: false, limit: 255
      t.integer     :user_agent_id,       null: false
      t.string      :client_version,      null: false, limit: 255
      t.timestamps                        null: false
    end

    add_column :users, :webauthn_id, :string, null: true

    add_column :auth_tokens, :fulfilled, :boolean, null: false, default: false
  end
end
