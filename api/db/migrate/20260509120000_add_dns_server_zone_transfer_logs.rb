class AddDnsServerZoneTransferLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :dns_server_zones, :last_transfer_log_id, :bigint, null: true
    add_column :dns_server_zones, :last_transfer_at, :datetime, null: true
    add_column :dns_server_zones, :last_transfer_status, :integer, null: true
    add_column :dns_server_zones, :last_transfer_reason_code, :string, limit: 40, null: true
    add_column :dns_server_zones, :last_transfer_reason, :string, limit: 255, null: true
    add_column :dns_server_zones, :last_transfer_primary_addr, :string, limit: 46, null: true
    add_column :dns_server_zones, :last_transfer_serial, :integer, unsigned: true, null: true
    add_index :dns_server_zones, :last_transfer_status

    create_table :dns_server_zone_transfer_logs do |t|
      t.references :dns_server_zone, null: false
      t.string     :event_key,       null: false, limit: 64
      t.datetime   :event_at,        null: false
      t.integer    :status,          null: false
      t.string     :reason_code,     null: true,  limit: 40
      t.string     :reason,          null: true,  limit: 255
      t.string     :primary_addr,    null: true,  limit: 46
      t.integer    :serial,          null: true,  unsigned: true
      t.text       :message,         null: true,  limit: 64_000
      t.text       :raw_message,     null: true,  limit: 64_000
      t.string     :source_cursor,   null: true,  limit: 191
      t.timestamps                   null: false
    end

    add_index :dns_server_zone_transfer_logs, :event_key, unique: true
    add_index :dns_server_zone_transfer_logs,
              %i[dns_server_zone_id event_at],
              name: 'idx_dns_server_zone_transfer_logs_on_zone_and_event_at'
  end
end
