class AddOauth2Provider < ActiveRecord::Migration[7.0]
  def change
    create_table :oauth2_clients do |t|
      t.string      :name,                           null: false
      t.string      :client_id,                      null: false
      t.string      :client_secret_hash,             null: false
      t.string      :redirect_uri,                   null: false
      t.timestamps                                   null: false
    end

    add_index :oauth2_clients, :client_id, unique: true

    create_table :oauth2_authorizations do |t|
      t.references  :oauth2_client,                  null: false
      t.references  :user,                           null: false
      t.string      :scope,                          null: true, limit: 255
      t.references  :code,                           null: true
      t.references  :user_session,                   null: true
      t.references  :refresh_token,                  null: true
      t.timestamps                                   null: false
    end
  end
end
