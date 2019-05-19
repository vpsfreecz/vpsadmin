class AddUserTotpDevices < ActiveRecord::Migration
  class User < ActiveRecord::Base ; end
  class UserTotpDevice < ActiveRecord::Base ; end

  def up
    create_table :user_totp_devices do |t|
      t.references  :user,                 null: false
      t.string      :label,                null: false, limit: 100
      t.boolean     :confirmed,            null: false, default: false
      t.boolean     :enabled,              null: false, default: false
      t.string      :secret,               null: true, limit: 32
      t.string      :recovery_code,        null: true, limit: 255
      t.integer     :last_verification_at, null: true
      t.integer     :use_count,            null: false, default: 0, unsigned: true
      t.datetime    :last_use_at,          null: true
      t.timestamps                         null: false
    end

    add_index :user_totp_devices, :user_id
    add_index :user_totp_devices, :enabled
    add_index :user_totp_devices, :secret, unique: true

    User.where(totp_enabled: true).each do |user|
      dev = UserTotpDevice.create!(
        user_id: user.id,
        label: 'Device',
        confirmed: true,
        enabled: true,
        secret: user.totp_secret,
        recovery_code: user.totp_recovery_code,
        last_verification_at: user.totp_last_use_at,
        last_use_at: Time.at(user.totp_last_use_at),
      )
      dev.update!(label: "Device ##{dev.id}")
    end

    remove_index :users, :totp_secret
    remove_column :users, :totp_enabled, :boolean, null: false, default: false
    remove_column :users, :totp_secret, :string, null: true, limit: 32
    remove_column :users, :totp_recovery_code, :string, null: true, limit: 255
    remove_column :users, :totp_last_use_at, :integer, null: true
  end

  def down
    add_column :users, :totp_enabled, :boolean, null: false, default: false
    add_column :users, :totp_secret, :string, null: true, limit: 32
    add_column :users, :totp_recovery_code, :string, null: true, limit: 255
    add_column :users, :totp_last_use_at, :integer, null: true

    add_index :users, :totp_secret, unique: true

    UserTotpDevice.where(
      enabled: true
    ).group('user_id').order('last_use_at DESC').each do |dev|
      user = User.find(dev.user_id)
      user.update!(
        totp_enabled: true,
        totp_secret: dev.secret,
        totp_recovery_code: dev.recovery_code,
        totp_last_use_at: dev.last_verification_at,
      )
    end

    drop_table :user_totp_devices
  end
end
