class AddUserNotificationDeliveryMethods < ActiveRecord::Migration[8.1]
  def up
    create_table :user_notification_delivery_methods do |t|
      t.references :user, null: false, index: false
      t.string :delivery_method, limit: 32, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end

    add_index :user_notification_delivery_methods, %i[user_id delivery_method],
              unique: true, name: 'idx_user_notification_delivery_methods_unique'
    add_index :user_notification_delivery_methods, %i[delivery_method enabled],
              name: 'idx_user_notification_delivery_methods_state'

    backfill_disabled_email_delivery_methods
  end

  def down
    drop_table :user_notification_delivery_methods
  end

  protected

  def backfill_disabled_email_delivery_methods
    return unless table_exists?(:users)
    return unless column_exists?(:users, :mailer_enabled)

    execute <<~SQL.squish
      INSERT INTO user_notification_delivery_methods
        (user_id, delivery_method, enabled, created_at, updated_at)
      SELECT
        id,
        'email',
        0,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      WHERE mailer_enabled = 0
    SQL
  end
end
