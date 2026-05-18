class RemoveStartedDnsServerZoneTransferLogs < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE dns_server_zones z
      LEFT JOIN dns_server_zone_transfer_logs current_log
        ON current_log.id = z.last_transfer_log_id
      LEFT JOIN dns_server_zone_transfer_logs replacement
        ON replacement.id = (
          SELECT l.id
          FROM dns_server_zone_transfer_logs l
          WHERE l.dns_server_zone_id = z.id
            AND l.status IN (1, 2)
          ORDER BY l.event_at DESC, l.id DESC
          LIMIT 1
        )
      SET
        z.last_transfer_log_id = replacement.id,
        z.last_transfer_at = replacement.event_at,
        z.last_transfer_status = replacement.status,
        z.last_transfer_reason_code = CASE
          WHEN replacement.status = 2 THEN replacement.reason_code
          ELSE NULL
        END,
        z.last_transfer_reason = CASE
          WHEN replacement.status = 2 THEN replacement.reason
          ELSE NULL
        END,
        z.last_transfer_primary_addr = replacement.primary_addr,
        z.last_transfer_serial = replacement.serial
      WHERE z.last_transfer_status = 0
         OR current_log.status = 0
    SQL

    execute 'DELETE FROM dns_server_zone_transfer_logs WHERE status = 0'

    execute <<~SQL
      UPDATE dns_server_zone_transfer_logs
      SET status = CASE status
        WHEN 1 THEN 0
        WHEN 2 THEN 1
      END
      WHERE status IN (1, 2)
    SQL

    execute <<~SQL
      UPDATE dns_server_zones
      SET last_transfer_status = CASE last_transfer_status
        WHEN 1 THEN 0
        WHEN 2 THEN 1
      END
      WHERE last_transfer_status IN (1, 2)
    SQL
  end

  def down
    execute <<~SQL
      UPDATE dns_server_zone_transfer_logs
      SET status = CASE status
        WHEN 0 THEN 1
        WHEN 1 THEN 2
      END
      WHERE status IN (0, 1)
    SQL

    execute <<~SQL
      UPDATE dns_server_zones
      SET last_transfer_status = CASE last_transfer_status
        WHEN 0 THEN 1
        WHEN 1 THEN 2
      END
      WHERE last_transfer_status IN (0, 1)
    SQL
  end
end
