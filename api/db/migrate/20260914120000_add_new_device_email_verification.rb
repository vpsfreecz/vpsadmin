class AddNewDeviceEmailVerification < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :enable_new_device_email_verification, :boolean, null: false, default: false
    add_column :oauth2_authorizations, :login_authentication, :text

    create_table :email_login_rate_limits do |t|
      t.string :bucket, null: false, limit: 100
      t.datetime :window_start, null: false
      t.datetime :expires_at, null: false
      t.integer :count, null: false, default: 0
    end
    add_index :email_login_rate_limits, %i[bucket window_start], unique: true,
                                                                 name: 'email_login_rate_limits_bucket'
    add_index :email_login_rate_limits, :expires_at
  end
end
