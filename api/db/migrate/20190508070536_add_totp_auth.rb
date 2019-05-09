class AddTotpAuth < ActiveRecord::Migration
  def change
    create_table :auth_tokens do |t|
      t.references  :token,           null: false
      t.references  :user,            null: false
      t.string      :opts,            null: true
      t.datetime    :created_at,      null: false
    end

    add_column :users, :totp_enabled, :boolean, null: false, default: false
    add_column :users, :totp_secret, :string, null: true, limit: 32
    add_column :users, :totp_recovery_code, :string, null: true, limit: 255
    add_column :users, :totp_last_use_at, :integer, null: true

    add_index :users, :totp_secret, unique: true
  end
end
