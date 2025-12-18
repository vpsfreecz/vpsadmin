class AddVncSupport < ActiveRecord::Migration[7.2]
  def change
    create_table :vnc_tokens do |t|
      t.references  :user_session,    null: false
      t.references  :vps,             null: false
      t.references  :client_token,    null: true, limit: 100, index: false
      t.references  :node_token,      null: true, limit: 100, index: false
      t.datetime    :expiration,      null: false
      t.timestamps
    end

    add_index :vnc_tokens, :client_token_id, unique: true
    add_index :vnc_tokens, :node_token_id, unique: true
  end
end
