module VpsAdmin::API::Tasks
  class Transfer < Base
    # Process real-time IP transfers
    def process
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("
          INSERT INTO ip_traffics (
            ip_address_id, user_id, protocol, role,
            packets_in, packets_out, bytes_in, bytes_out,
            created_at
          )

          SELECT
            ip_address_id, user_id, protocol, role,
            SUM(packets_in) AS spi, SUM(packets_out) AS spo,
            SUM(bytes_in) AS sbi, SUM(bytes_out) AS sbo,
            DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')
          FROM `ip_recent_traffics` r
          WHERE created_at < DATE_SUB(NOW(), INTERVAL 60 SECOND)
          GROUP BY ip_address_id,
                   user_id,
                   protocol,
                   role,
                   DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')

          ON DUPLICATE KEY UPDATE
            packets_in = packets_in + values(packets_in),
            packets_out = packets_out + values(packets_out),
            bytes_in = bytes_in + values(bytes_in),
            bytes_out = bytes_out + values(bytes_out)
        ")

        ActiveRecord::Base.connection.execute("
          INSERT INTO ip_traffic_monthly_summaries (
            ip_address_id, user_id, protocol, role,
            packets_in, packets_out, bytes_in, bytes_out,
            created_at, year, month
          )

          SELECT
            ip_address_id, user_id, protocol, role,
            SUM(packets_in) AS spi, SUM(packets_out) AS spo,
            SUM(bytes_in) AS sbi, SUM(bytes_out) AS sbo,
            DATE_FORMAT(created_at, '%Y-%m-01 00:00:00'),
            YEAR(created_at), MONTH(created_at)
          FROM `ip_recent_traffics` r
          WHERE created_at < DATE_SUB(NOW(), INTERVAL 60 SECOND)
          GROUP BY ip_address_id,
                   user_id,
                   protocol,
                   role,
                   DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')

          ON DUPLICATE KEY UPDATE
            packets_in = packets_in + values(packets_in),
            packets_out = packets_out + values(packets_out),
            bytes_in = bytes_in + values(bytes_in),
            bytes_out = bytes_out + values(bytes_out)
        ")

        ActiveRecord::Base.connection.execute('
          DELETE
          FROM ip_recent_traffics
          WHERE created_at < DATE_SUB(NOW(), INTERVAL 60 SECOND)
        ')
      end
    end
  end
end
