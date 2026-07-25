class RetireMailerNodes < ActiveRecord::Migration[8.1]
  MAILER_ROLE = 2

  def up
    execute <<~SQL.squish
      UPDATE nodes
      SET active = 0
      WHERE role = #{MAILER_ROLE}
        AND active <> 0
    SQL
  end

  def down
    # Intentionally no-op: rollback must not reactivate mailer rows that may
    # have been disabled by operators before this migration.
  end
end
