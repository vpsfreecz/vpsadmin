class AddEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :notification_receivers do |t|
      t.references  :user,                     null: false
      t.string      :label,                    null: false, limit: 255
      t.text        :description,              null: true
      t.boolean     :enabled,                  null: false, default: true
      t.boolean     :mute,                     null: false, default: false
      t.timestamps                             null: false
    end

    add_index :notification_receivers, %i[user_id enabled],
              name: 'index_notification_receivers_on_user_enabled'
    add_index :notification_receivers, %i[user_id mute],
              name: 'index_notification_receivers_on_user_mute'

    create_table :notification_receiver_actions do |t|
      t.references  :notification_receiver,    null: false,
                                               index: { name: 'idx_receiver_actions_on_receiver' }
      t.integer     :action,                   null: false
      t.string      :label,                    null: true, limit: 255
      t.integer     :target_kind,              null: false, default: 0
      t.text        :target_value,             null: true
      t.string      :template_name,            null: true, limit: 100
      t.text        :config,                   null: true
      t.text        :secret,                   null: true
      t.string      :verification_token,       null: true, limit: 255
      t.datetime    :verified_at,              null: true
      t.boolean     :enabled,                  null: false, default: true
      t.text        :last_error,               null: true
      t.timestamps                             null: false
    end

    add_index :notification_receiver_actions, %i[notification_receiver_id action enabled],
              name: 'idx_receiver_actions_on_receiver_action_enabled'
    add_index :notification_receiver_actions, :verification_token, unique: true

    create_table :event_routes do |t|
      t.references  :user,                     null: false
      t.bigint      :parent_id,                null: true
      t.bigint      :notification_receiver_id, null: true
      t.string      :label,                    null: true, limit: 255
      t.integer     :position,                 null: false, default: 0
      t.boolean     :enabled,                  null: false, default: true
      t.string      :event_type,               null: true, limit: 100
      t.string      :event_type_pattern,       null: true, limit: 100
      t.boolean     :continue,                 null: false, default: false
      t.bigint      :hit_count,                null: false, default: 0
      t.timestamps                             null: false
    end

    add_index :event_routes, %i[user_id parent_id position id],
              name: 'index_event_routes_on_user_parent_position'
    add_index :event_routes, :enabled
    add_index :event_routes, :event_type
    add_index :event_routes, :parent_id
    add_index :event_routes, :notification_receiver_id

    create_table :event_route_matchers do |t|
      t.references  :event_route,              null: false
      t.string      :field,                    null: false, limit: 100
      t.string      :operator,                 null: false, limit: 50
      t.text        :value,                    null: false
      t.timestamps                             null: false
    end

    create_table :events do |t|
      t.references  :user,                     null: true
      t.string      :event_type,               null: false, limit: 100
      t.string      :category,                 null: false, limit: 100
      t.integer     :severity,                 null: false
      t.string      :subject,                  null: false, limit: 255
      t.text        :summary,                  null: true
      t.text        :parameters,               null: true
      t.string      :source_class,             null: true, limit: 100
      t.bigint      :source_id,                null: true
      t.references  :vps,                      null: true
      t.string      :ip_addr,                  null: true, limit: 46
      t.integer     :routing_state,            null: false, default: 0
      t.bigint      :matched_event_route_id,   null: true
      t.timestamps                             null: false
    end

    add_index :events, :event_type
    add_index :events, :category
    add_index :events, :severity
    add_index :events, :routing_state
    add_index :events, :created_at
    add_index :events, :matched_event_route_id

    create_table :event_deliveries do |t|
      t.references  :event,                    null: false
      t.references  :event_route,              null: true
      t.references  :notification_receiver,    null: true
      t.references  :notification_receiver_action, null: true,
                                                   index: { name: 'idx_event_deliveries_on_receiver_action' }
      t.integer     :action,                   null: false
      t.integer     :target_kind,              null: false
      t.text        :target_value,             null: true
      t.string      :target_label,             null: true, limit: 255
      t.string      :template_name,            null: true, limit: 100
      t.integer     :state,                    null: false
      t.integer     :mail_log_id,              null: true
      t.integer     :transaction_id,           null: true
      t.integer     :attempt_count,            null: false, default: 0
      t.datetime    :next_attempt_at,          null: true
      t.datetime    :last_attempt_at,          null: true
      t.string      :provider_message_id,      null: true, limit: 255
      t.integer     :response_status,          null: true
      t.text        :response_body,            null: true
      t.text        :error_summary,            null: true
      t.timestamps                             null: false
    end

    add_index :event_deliveries, %i[event_id action state]
    add_index :event_deliveries, :state
    add_index :event_deliveries, :next_attempt_at
    add_index :event_deliveries, :mail_log_id
    add_index :event_deliveries, :transaction_id

    backfill_default_routes
  end

  def down
    drop_table :event_deliveries
    drop_table :events
    drop_table :event_route_matchers
    drop_table :event_routes
    drop_table :notification_receiver_actions
    drop_table :notification_receivers
  end

  protected

  def backfill_default_routes
    return unless table_exists?(:users)

    say_with_time('Creating default event receivers and routes') do
      execute <<~SQL.squish
        INSERT INTO notification_receivers
          (user_id, label, description, enabled, mute, created_at, updated_at)
        SELECT
          id,
          CASE WHEN mailer_enabled = 1 THEN 'Default e-mail' ELSE 'Do not notify' END,
          CASE
            WHEN mailer_enabled = 1 THEN 'Created from the existing mailer setting'
            ELSE 'Created from the disabled mailer setting'
          END,
          1,
          CASE WHEN mailer_enabled = 1 THEN 0 ELSE 1 END,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM users
      SQL

      execute <<~SQL.squish
        INSERT INTO notification_receiver_actions
          (notification_receiver_id, action, label, target_kind, target_value,
           template_name, enabled, created_at, updated_at)
        SELECT
          notification_receivers.id,
          0,
          'Default e-mail',
          0,
          NULL,
          NULL,
          1,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
        INNER JOIN users ON users.id = notification_receivers.user_id
        WHERE users.mailer_enabled = 1
      SQL

      execute <<~SQL.squish
        INSERT INTO event_routes
          (user_id, parent_id, notification_receiver_id, label, position,
           enabled, event_type, event_type_pattern, `continue`, hit_count,
           created_at, updated_at)
        SELECT
          user_id,
          NULL,
          id,
          'Default route',
          10000,
          1,
          NULL,
          NULL,
          0,
          0,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM notification_receivers
      SQL
    end
  end
end
