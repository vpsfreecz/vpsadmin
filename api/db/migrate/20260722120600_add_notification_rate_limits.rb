class AddNotificationRateLimits < ActiveRecord::Migration[8.1]
  def change
    create_table :user_notification_rate_limits do |t|
      t.references :user, null: false, index: false
      t.string :delivery_method, limit: 32, null: false
      t.string :period, limit: 16, null: false
      t.integer :limit_count, null: false
      t.timestamps null: false
    end

    add_index :user_notification_rate_limits, %i[user_id delivery_method period],
              unique: true,
              name: 'idx_user_notification_rate_limits_unique'
    add_index :user_notification_rate_limits, %i[delivery_method period],
              name: 'idx_user_notification_rate_limits_method_period'

    create_table :notification_rate_limit_states do |t|
      t.references :user, null: false, index: false
      t.string :delivery_method, limit: 32, null: false
      t.timestamps null: false
    end

    add_index :notification_rate_limit_states, %i[user_id delivery_method],
              unique: true,
              name: 'idx_notification_rate_limit_states_unique'

    add_reference :event_delivery_attempts,
                  :recipient_user,
                  null: true,
                  index: {
                    name: 'idx_event_delivery_attempts_on_recipient_user'
                  }

    add_index :event_delivery_attempts, %i[recipient_user_id action started_at],
              name: 'idx_delivery_attempts_on_recipient_action_started'
  end
end
