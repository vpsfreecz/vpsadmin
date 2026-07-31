class NormalizeDefaultNotificationLabels < ActiveRecord::Migration[8.1]
  DEFAULT_EMAIL_LABEL = 'Default'
  LEGACY_DEFAULT_EMAIL_LABEL = 'Default e-mail'
  DEFAULT_EMAIL_DESCRIPTION = 'Default notification receiver'
  LEGACY_DEFAULT_EMAIL_DESCRIPTION = 'Created from the existing mailer setting'

  def up
    execute <<~SQL.squish
      UPDATE notification_receivers
      SET label = #{quote(DEFAULT_EMAIL_LABEL)}
      WHERE label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
        AND mute = 0
        AND description IN (
          #{quote(DEFAULT_EMAIL_DESCRIPTION)},
          #{quote(LEGACY_DEFAULT_EMAIL_DESCRIPTION)}
        )
    SQL

    execute <<~SQL.squish
      UPDATE notification_targets
      SET label = #{quote(DEFAULT_EMAIL_LABEL)}
      WHERE label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
        AND action = 'email'
        AND target_kind = 0
        AND identity_key = 'default'
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE notification_receivers
      SET label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
      WHERE label = #{quote(DEFAULT_EMAIL_LABEL)}
        AND mute = 0
        AND description IN (
          #{quote(DEFAULT_EMAIL_DESCRIPTION)},
          #{quote(LEGACY_DEFAULT_EMAIL_DESCRIPTION)}
        )
    SQL

    execute <<~SQL.squish
      UPDATE notification_targets
      SET label = #{quote(LEGACY_DEFAULT_EMAIL_LABEL)}
      WHERE label = #{quote(DEFAULT_EMAIL_LABEL)}
        AND action = 'email'
        AND target_kind = 0
        AND identity_key = 'default'
    SQL
  end
end
