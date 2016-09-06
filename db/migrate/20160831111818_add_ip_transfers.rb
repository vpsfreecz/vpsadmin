class AddIpTransfers < ActiveRecord::Migration
  def up
    %i(ip_traffics ip_recent_traffics).each do |table|
      create_table table do |t|
        t.references  :ip_address,     null: false
        t.references  :user,           null: true
        t.integer     :protocol,       null: false
        t.integer     :packets_in,     null: false, limit: 8, unsigned: true, default: 0
        t.integer     :packets_out,    null: false, limit: 8, unsigned: true, default: 0
        t.integer     :bytes_in,       null: false, limit: 8, unsigned: true, default: 0
        t.integer     :bytes_out,      null: false, limit: 8, unsigned: true, default: 0
        t.datetime    :created_at,     null: false
      end

      add_index table, %i(ip_address_id user_id protocol created_at), unique: true,
                name: :transfers_unique
      add_index table, :ip_address_id
      add_index table, :user_id
    end

    if ENV['MIGRATE_TRAFFIC_DATA'] != 'no' && table_exists?(:transfered)
      {
          transfered: :ip_traffics,
          transfered_recent: :ip_recent_traffics,
      }.each do |src, dst|
        ActiveRecord::Base.connection.execute("
            INSERT INTO #{dst} (
              ip_address_id, user_id, protocol, packets_in, packets_out,
              bytes_in, bytes_out, created_at
            )

            SELECT
              vps_ip.ip_id,
              IF(vps_ip.user_id IS NULL, vps.m_id, vps_ip.user_id),
              (
                CASE tr_proto
                WHEN 'all' THEN 0
                WHEN 'tcp' THEN 1
                WHEN 'udp' THEN 2
                END
              ), tr_packets_in, tr_packets_out, tr_bytes_in, tr_bytes_out, tr_date
            FROM #{src}
            INNER JOIN vps_ip ON vps_ip.ip_addr = tr_ip COLLATE utf8_general_ci
            LEFT JOIN vps ON vps.vps_id = vps_ip.vps_id
            ORDER BY tr_date, tr_ip, tr_proto
        ")

        drop_table src
      end
    end
  end

  # The rollback will not generate the exact same table, because ActiveRecord
  # does not support composite primary keys, i.e. there will be column `id`
  # as a primary key.
  def down
    %i(transfered transfered_recent).each do |table|
      create_table table do |t|
        t.string      :tr_ip,             null: false, limit: 127
        t.string      :tr_proto,          null: false, limit: 4
        t.integer     :tr_packets_in,     null: false, limit: 8, unsigned: true, default: 0
        t.integer     :tr_packets_out,    null: false, limit: 8, unsigned: true, default: 0
        t.integer     :tr_bytes_in,       null: false, limit: 8, unsigned: true, default: 0
        t.integer     :tr_bytes_out,      null: false, limit: 8, unsigned: true, default: 0
        t.datetime    :tr_date,           null: false
      end

      add_index table, %i(tr_ip tr_proto tr_date), unique: true,
                name: :transfers_unique
    end
     
    return if ENV['MIGRATE_TRAFFIC_DATA'] == 'no'

    {
        ip_traffics: :transfered,
        ip_recent_traffics: :transfered_recent,
    }.each do |src, dst|
      ActiveRecord::Base.connection.execute("
          INSERT INTO #{dst} (
            tr_ip, tr_proto, tr_packets_in, tr_packets_out, tr_bytes_in, tr_bytes_out,
            tr_date
          )

          SELECT
            vps_ip.ip_addr, (
              CASE protocol
              WHEN 0 THEN 'all'
              WHEN 1 THEN 'tcp'
              WHEN 2 THEN 'udp'
              END
            ), packets_in, packets_out, bytes_in, bytes_out, created_at
          FROM #{src}
          INNER JOIN vps_ip ON vps_ip.ip_id = #{src}.ip_address_id
          ORDER BY created_at, ip_address_id, protocol
      ")

      drop_table src
    end
  end
end
