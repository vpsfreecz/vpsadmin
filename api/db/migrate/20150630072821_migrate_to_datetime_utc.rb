# Convert all timestamp columns used by the API to datetime and also to UTC
# timezone.
# Columns still not used by the API are not converted, e.g. network transfers.
class MigrateToDatetimeUtc < ActiveRecord::Migration
  class Vps < ActiveRecord::Base
    self.table_name = 'vps'
    self.primary_key = 'vps_id'
  end

  class User < ActiveRecord::Base
    self.table_name = 'members'
    self.primary_key = 'm_id'
  end

  class Transaction < ActiveRecord::Base
    self.primary_key = 't_id'
  end

  class VpsConsole < ActiveRecord::Base
    self.table_name = 'vps_console'
  end

  class VpsStatus < ActiveRecord::Base
    self.table_name = 'vps_status'
  end

  class NodeStatus < ActiveRecord::Base
    self.table_name = 'servers_status'
    self.primary_key = 'server_id'
  end

  def change
    add_timestamps :vps
    add_column :members, :paid_until, :datetime, null: true
    add_column :members, :last_activity_at, :datetime, null: true
    add_column :transactions, :created_at, :datetime, null: true
    add_column :transactions, :started_at, :datetime, null: true
    add_column :transactions, :finished_at, :datetime, null: true
    add_column :vps_status, :created_at, :datetime, null: true
    add_column :servers_status, :created_at, :datetime, null: true

    reversible do |dir|
      dir.up do
        Vps.where.not(vps_created: nil).update_all(
            "created_at = CONVERT_TZ(FROM_UNIXTIME(vps_created), 'Europe/Prague', 'UTC')"
        )

        User.where.not(m_created: nil).update_all(
            "created_at = CONVERT_TZ(FROM_UNIXTIME(m_created), 'Europe/Prague', 'UTC')"
        )

        User.where("m_paid_until IS NOT NULL AND m_paid_until != ''").update_all(
            "paid_until = CONVERT_TZ(FROM_UNIXTIME(m_paid_until), 'Europe/Prague', 'UTC')"
        )

        User.where.not(m_last_activity: nil).update_all(
            "last_activity_at = CONVERT_TZ(FROM_UNIXTIME(m_last_activity), 'Europe/Prague', 'UTC')"
        )

        Transaction.where.not(t_time: nil).update_all(
            "created_at = CONVERT_TZ(FROM_UNIXTIME(t_time), 'Europe/Prague', 'UTC')"
        )

        Transaction.where.not(t_real_start: nil).update_all(
            "started_at = CONVERT_TZ(FROM_UNIXTIME(t_real_start), 'Europe/Prague', 'UTC')"
        )

        Transaction.where.not(t_end: nil).update_all(
            "finished_at = CONVERT_TZ(FROM_UNIXTIME(t_end), 'Europe/Prague', 'UTC')"
        )

        VpsConsole.all.update_all(
            "expiration = CONVERT_TZ(expiration, 'Europe/Prague', 'UTC')"
        )

        VpsStatus.all.update_all(
            "created_at = CONVERT_TZ(FROM_UNIXTIME(`timestamp`), 'Europe/Prague', 'UTC')"
        )

        change_column_null :vps_status, :created_at, false

        NodeStatus.all.update_all(
            "created_at = CONVERT_TZ(FROM_UNIXTIME(`timestamp`), 'Europe/Prague', 'UTC')"
        )

        change_column_null :servers_status, :created_at, false
      end

      dir.down do
        Vps.where.not(created_at: nil).update_all(
            "vps_created = UNIX_TIMESTAMP(CONVERT_TZ(created_at, 'UTC', 'Europe/Prague'))"
        )

        User.where.not(created_at: nil).update_all(
            "m_created = UNIX_TIMESTAMP(CONVERT_TZ(created_at, 'UTC', 'Europe/Prague'))"
        )

        User.where.not(paid_until: nil).update_all(
            "m_paid_until = UNIX_TIMESTAMP(CONVERT_TZ(paid_until, 'UTC', 'Europe/Prague'))"
        )

        User.where.not(last_activity_at: nil).update_all(
            "m_last_activity = UNIX_TIMESTAMP(CONVERT_TZ(last_activity_at, 'UTC', 'Europe/Prague'))"
        )

        Transaction.where.not(created_at: nil).update_all(
            "t_time = UNIX_TIMESTAMP(CONVERT_TZ(created_at, 'UTC', 'Europe/Prague'))"
        )

        Transaction.where.not(started_at: nil).update_all(
            "t_real_start = UNIX_TIMESTAMP(CONVERT_TZ(started_at, 'UTC', 'Europe/Prague'))"
        )

        Transaction.where.not(finished_at: nil).update_all(
            "t_end = UNIX_TIMESTAMP(CONVERT_TZ(finished_at, 'UTC', 'Europe/Prague'))"
        )

        VpsConsole.all.update_all(
            "expiration = CONVERT_TZ(expiration, 'UTC', 'Europe/Prague')"
        )

        VpsStatus.all.update_all(
            "`timestamp` = UNIX_TIMESTAMP(CONVERT_TZ(created_at, 'UTC', 'Europe/Prague'))"
        )

        change_column_null :vps_status, :timestamp, false

        NodeStatus.all.update_all(
            "`timestamp` = UNIX_TIMESTAMP(CONVERT_TZ(created_at, 'UTC', 'Europe/Prague'))"
        )

        change_column_null :servers_status, :timestamp, false
      end
    end

    remove_column :vps, :vps_created, :integer, null: true
    remove_column :members, :m_created, :integer, null: true
    remove_column :members, :m_paid_until, :string, limit: 32, null: true
    remove_column :members, :m_last_activity, :integer, null: true
    remove_column :transactions, :t_time, :integer, null: true
    remove_column :transactions, :t_real_start, :integer, null: true
    remove_column :transactions, :t_end, :integer, null: true
    remove_column :vps_status, :timestamp, :integer, null: true
    remove_column :servers_status, :timestamp, :integer, null: true
  end
end
