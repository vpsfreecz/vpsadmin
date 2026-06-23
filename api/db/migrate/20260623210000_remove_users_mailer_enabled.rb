class RemoveUsersMailerEnabled < ActiveRecord::Migration[8.1]
  DEFAULT_EMAIL_LABEL = 'Default e-mail'.freeze
  DEFAULT_MUTE_LABEL = 'Mute'.freeze
  LEGACY_DEFAULT_MUTE_LABEL = 'Do not notify'.freeze
  DEFAULT_EMAIL_DESCRIPTION = 'Default notification receiver'.freeze
  DEFAULT_MUTE_DESCRIPTION = 'Default muted notification receiver'.freeze
  LEGACY_DEFAULT_EMAIL_DESCRIPTION = 'Created from the existing mailer setting'.freeze
  LEGACY_DEFAULT_MUTE_DESCRIPTION = 'Created from the disabled mailer setting'.freeze

  def up
    return unless table_exists?(:users)

    preserve_disabled_mailers_as_email_disabled
    ensure_default_email_receivers
    ensure_default_email_actions
    normalize_legacy_mute_receivers
    ensure_default_mute_receivers
    ensure_default_routes

    remove_column :users, :mailer_enabled if column_exists?(:users, :mailer_enabled)
  end

  def down
    return unless table_exists?(:users)

    unless column_exists?(:users, :mailer_enabled)
      add_column :users, :mailer_enabled, :boolean, null: false, default: true
    end

    return unless table_exists?(:user_notification_delivery_methods)

    execute <<~SQL.squish
      UPDATE users
      SET mailer_enabled = 0
      WHERE EXISTS (
        SELECT 1
        FROM user_notification_delivery_methods
        WHERE user_notification_delivery_methods.user_id = users.id
          AND user_notification_delivery_methods.delivery_method = 'email'
          AND user_notification_delivery_methods.enabled = 0
      )
    SQL
  end

  protected

  def preserve_disabled_mailers_as_email_disabled
    return unless table_exists?(:user_notification_delivery_methods)
    return unless column_exists?(:users, :mailer_enabled)

    execute <<~SQL.squish
      UPDATE user_notification_delivery_methods
      INNER JOIN users
        ON users.id = user_notification_delivery_methods.user_id
      SET user_notification_delivery_methods.enabled = 0
      WHERE users.mailer_enabled = 0
        AND user_notification_delivery_methods.delivery_method = 'email'
    SQL

    execute <<~SQL.squish
      INSERT INTO user_notification_delivery_methods
        (user_id, delivery_method, enabled, created_at, updated_at)
      SELECT
        users.id,
        'email',
        0,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      WHERE users.mailer_enabled = 0
        AND NOT EXISTS (
          SELECT 1
          FROM user_notification_delivery_methods
          WHERE user_notification_delivery_methods.user_id = users.id
            AND user_notification_delivery_methods.delivery_method = 'email'
        )
    SQL
  end

  def ensure_default_email_receivers
    return unless table_exists?(:notification_receivers)

    execute <<~SQL.squish
      INSERT INTO notification_receivers
        (user_id, label, description, enabled, mute, created_at, updated_at)
      SELECT
        users.id,
        #{quote(DEFAULT_EMAIL_LABEL)},
        #{quote(DEFAULT_EMAIL_DESCRIPTION)},
        1,
        0,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      WHERE NOT EXISTS (
        SELECT 1
        FROM notification_receivers
        WHERE notification_receivers.user_id = users.id
          AND notification_receivers.mute = 0
          AND notification_receivers.label = #{quote(DEFAULT_EMAIL_LABEL)}
          AND notification_receivers.description IN (
            #{quote(DEFAULT_EMAIL_DESCRIPTION)},
            #{quote(LEGACY_DEFAULT_EMAIL_DESCRIPTION)}
          )
      )
    SQL
  end

  def ensure_default_email_actions
    return unless table_exists?(:notification_receivers)
    return unless table_exists?(:notification_receiver_actions)

    execute <<~SQL.squish
      INSERT INTO notification_receiver_actions
        (notification_receiver_id, action, label, target_kind, target_value,
         enabled, created_at, updated_at)
      SELECT
        notification_receivers.id,
        'email',
        #{quote(DEFAULT_EMAIL_LABEL)},
        0,
        NULL,
        1,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM notification_receivers
      WHERE notification_receivers.mute = 0
        AND notification_receivers.label = #{quote(DEFAULT_EMAIL_LABEL)}
        AND notification_receivers.description IN (
          #{quote(DEFAULT_EMAIL_DESCRIPTION)},
          #{quote(LEGACY_DEFAULT_EMAIL_DESCRIPTION)}
        )
        AND NOT EXISTS (
          SELECT 1
          FROM notification_receiver_actions
          WHERE notification_receiver_actions.notification_receiver_id =
                notification_receivers.id
            AND notification_receiver_actions.action = 'email'
            AND notification_receiver_actions.target_kind = 0
        )
    SQL
  end

  def normalize_legacy_mute_receivers
    return unless table_exists?(:notification_receivers)

    execute <<~SQL.squish
      UPDATE notification_receivers
      SET label = #{quote(DEFAULT_MUTE_LABEL)},
          description = #{quote(DEFAULT_MUTE_DESCRIPTION)}
      WHERE mute = 1
        AND label = #{quote(LEGACY_DEFAULT_MUTE_LABEL)}
        AND description = #{quote(LEGACY_DEFAULT_MUTE_DESCRIPTION)}
    SQL
  end

  def ensure_default_mute_receivers
    return unless table_exists?(:notification_receivers)

    execute <<~SQL.squish
      INSERT INTO notification_receivers
        (user_id, label, description, enabled, mute, created_at, updated_at)
      SELECT
        users.id,
        #{quote(DEFAULT_MUTE_LABEL)},
        #{quote(DEFAULT_MUTE_DESCRIPTION)},
        1,
        1,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      WHERE NOT EXISTS (
        SELECT 1
        FROM notification_receivers
        WHERE notification_receivers.user_id = users.id
          AND notification_receivers.mute = 1
          AND notification_receivers.label = #{quote(DEFAULT_MUTE_LABEL)}
          AND notification_receivers.description = #{quote(DEFAULT_MUTE_DESCRIPTION)}
      )
    SQL
  end

  def ensure_default_routes
    return unless table_exists?(:event_routes)
    return unless table_exists?(:notification_receivers)
    return unless column_exists?(:users, :mailer_enabled)

    execute <<~SQL.squish
      INSERT INTO event_routes
        (user_id, parent_id, notification_receiver_id, label, position,
         enabled, event_type, event_type_pattern, `continue`,
         default_route, single_use, spent_at, expires_at, hit_count,
         created_at, updated_at)
      SELECT
        users.id,
        NULL,
        notification_receivers.id,
        'Default route',
        10000,
        1,
        NULL,
        NULL,
        0,
        1,
        0,
        NULL,
        NULL,
        0,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM users
      INNER JOIN notification_receivers
        ON notification_receivers.id = (
          SELECT generated_receiver.id
          FROM notification_receivers AS generated_receiver
          WHERE generated_receiver.user_id = users.id
            AND (
              (
                users.mailer_enabled = 0
                AND generated_receiver.mute = 1
                AND generated_receiver.label = #{quote(DEFAULT_MUTE_LABEL)}
                AND generated_receiver.description = #{quote(DEFAULT_MUTE_DESCRIPTION)}
              )
              OR (
                users.mailer_enabled != 0
                AND generated_receiver.mute = 0
                AND generated_receiver.label = #{quote(DEFAULT_EMAIL_LABEL)}
                AND generated_receiver.description IN (
                  #{quote(DEFAULT_EMAIL_DESCRIPTION)},
                  #{quote(LEGACY_DEFAULT_EMAIL_DESCRIPTION)}
                )
              )
            )
          ORDER BY generated_receiver.id
          LIMIT 1
        )
      WHERE NOT EXISTS (
        SELECT 1
        FROM event_routes
        WHERE event_routes.user_id = users.id
          AND event_routes.parent_id IS NULL
          AND event_routes.default_route = 1
      )
    SQL
  end

  def quote(value)
    connection.quote(value)
  end
end
