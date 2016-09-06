class AddMonthlySummaryForIpTraffics < ActiveRecord::Migration
  def change
    create_table :ip_traffic_monthly_summaries do |t|
      t.references  :ip_address,     null: false
      t.references  :user,           null: true
      t.integer     :protocol,       null: false
      t.integer     :role,           null: false
      t.integer     :packets_in,     null: false, limit: 8, unsigned: true, default: 0
      t.integer     :packets_out,    null: false, limit: 8, unsigned: true, default: 0
      t.integer     :bytes_in,       null: false, limit: 8, unsigned: true, default: 0
      t.integer     :bytes_out,      null: false, limit: 8, unsigned: true, default: 0
      t.datetime    :created_at,     null: false
      t.integer     :year,           null: false
      t.integer     :month,          null: false
    end

    add_index :ip_traffic_monthly_summaries,
              %i(ip_address_id user_id protocol role created_at),
              unique: true, name: :ip_traffic_monthly_summaries_unique
    add_index :ip_traffic_monthly_summaries, :ip_address_id
    add_index :ip_traffic_monthly_summaries, :user_id
    add_index :ip_traffic_monthly_summaries, :protocol
    add_index :ip_traffic_monthly_summaries, :year
    add_index :ip_traffic_monthly_summaries, :month
    add_index :ip_traffic_monthly_summaries, %i(year month)
    add_index :ip_traffic_monthly_summaries, %i(ip_address_id year month),
              name: :ip_traffic_monthly_summaries_ip_year_month

    return if ENV['MIGRATE_TRAFFIC_DATA'] == 'no'

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute("
            INSERT INTO ip_traffic_monthly_summaries
              (ip_address_id, user_id, protocol, role,
              packets_in, packets_out, bytes_in, bytes_out,
              created_at, year, month)

            SELECT
              ip_address_id, user_id, protocol, role,
              SUM(packets_in), SUM(packets_out), SUM(bytes_in), SUM(bytes_out),
              DATE_FORMAT(created_at, '%Y-%m-01 00:00:00'),
              YEAR(created_at), MONTH(created_at)
            FROM ip_traffics
            GROUP BY
              ip_address_id,
              user_id,
              protocol,
              YEAR(created_at),
              MONTH(created_at)
            ORDER BY created_at, ip_address_id
        ")
      end
    end
  end
end
