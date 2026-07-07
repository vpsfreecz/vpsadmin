# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260708120000_remove_empty_dns_transfer_success_logs')

RSpec.describe RemoveEmptyDnsTransferSuccessLogs do
  def define_transfer_log_schema
    define_schema do
      create_table :dns_server_zones do |t|
        t.datetime :last_transfer_at
        t.integer :last_transfer_status
        t.string :last_transfer_reason_code, limit: 40
        t.string :last_transfer_reason, limit: 255
        t.string :last_transfer_primary_addr, limit: 46
        t.integer :last_transfer_serial, unsigned: true
        t.bigint :last_transfer_log_id
      end

      create_table :dns_server_zone_transfer_logs do |t|
        t.references :dns_server_zone, null: false
        t.string :event_key, null: false, limit: 64
        t.datetime :event_at, null: false
        t.integer :status, null: false
        t.string :reason_code, limit: 40
        t.string :reason, limit: 255
        t.string :primary_addr, limit: 46
        t.integer :serial, unsigned: true
        t.text :message, limit: 64_000
        t.text :raw_message, limit: 64_000
        t.string :source_cursor, limit: 191
        t.timestamps null: false
      end
    end
  end

  def insert_server_zone(last_transfer_log_id: nil, **attrs)
    insert_row(
      :dns_server_zones,
      {
        last_transfer_log_id:,
        last_transfer_at: attrs[:last_transfer_at],
        last_transfer_status: attrs[:last_transfer_status],
        last_transfer_reason_code: attrs[:last_transfer_reason_code],
        last_transfer_reason: attrs[:last_transfer_reason],
        last_transfer_primary_addr: attrs[:last_transfer_primary_addr],
        last_transfer_serial: attrs[:last_transfer_serial]
      }
    )
  end

  def insert_transfer_log(server_zone_id, attrs)
    now = timestamp

    insert_row(
      :dns_server_zone_transfer_logs,
      {
        dns_server_zone_id: server_zone_id,
        event_key: attrs.fetch(:event_key),
        event_at: attrs.fetch(:event_at),
        status: attrs.fetch(:status),
        reason_code: attrs[:reason_code],
        reason: attrs[:reason],
        primary_addr: attrs[:primary_addr],
        serial: attrs[:serial],
        message: attrs[:message],
        raw_message: attrs[:raw_message],
        source_cursor: attrs[:source_cursor],
        created_at: now,
        updated_at: now
      }
    )
  end

  def bogus_raw_message(zone: 'example.test', primary_addr: '192.0.2.1')
    "transfer of '#{zone}/IN' from #{primary_addr}#53: Transfer completed: " \
      '0 messages, 0 records, 0 bytes, 132.454 secs (0 bytes/sec) (serial 0)'
  end

  it 'removes bogus empty success rows and restores latest failed state' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    failed_at = timestamp
    bogus_at = timestamp + 1.minute
    failed_id = insert_transfer_log(
      server_zone_id,
      event_key: 'failed',
      event_at: failed_at,
      status: 1,
      reason_code: 'timeout',
      reason: 'The primary DNS server did not respond in time',
      primary_addr: '192.0.2.1',
      serial: nil,
      message: 'timed out',
      raw_message: "transfer of 'example.test/IN' from 192.0.2.1#53: Transfer status: timed out",
      source_cursor: 'cursor-failed'
    )
    bogus_id = insert_transfer_log(
      server_zone_id,
      event_key: 'bogus',
      event_at: bogus_at,
      status: 0,
      reason_code: nil,
      reason: nil,
      primary_addr: '192.0.2.1',
      serial: 0,
      message: 'Transfer completed successfully',
      raw_message: bogus_raw_message,
      source_cursor: 'cursor-bogus'
    )
    connection.update(<<~SQL.squish)
      UPDATE dns_server_zones
      SET last_transfer_log_id = #{bogus_id},
          last_transfer_at = #{connection.quote(bogus_at)},
          last_transfer_status = 0,
          last_transfer_reason_code = NULL,
          last_transfer_reason = NULL,
          last_transfer_primary_addr = '192.0.2.1',
          last_transfer_serial = 0
      WHERE id = #{server_zone_id}
    SQL

    migrate_up!

    expect(find_rows(:dns_server_zone_transfer_logs).map { |row| row.fetch('id').to_i }).to eq([failed_id])
    zone = find_row(:dns_server_zones, id: server_zone_id)
    expect(zone.fetch('last_transfer_log_id').to_i).to eq(failed_id)
    expect(zone.fetch('last_transfer_status').to_i).to eq(1)
    expect(zone.fetch('last_transfer_reason_code')).to eq('timeout')
    expect(zone.fetch('last_transfer_reason')).to eq('The primary DNS server did not respond in time')
    expect(zone.fetch('last_transfer_primary_addr')).to eq('192.0.2.1')
    expect(zone.fetch('last_transfer_serial')).to be_nil
  end

  it 'clears latest transfer state when only bogus rows remain' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    bogus_at = timestamp
    bogus_id = insert_transfer_log(
      server_zone_id,
      event_key: 'only-bogus',
      event_at: bogus_at,
      status: 0,
      reason_code: nil,
      reason: nil,
      primary_addr: '192.0.2.1',
      serial: 0,
      message: 'Transfer completed successfully',
      raw_message: bogus_raw_message,
      source_cursor: 'cursor-bogus'
    )
    connection.update(<<~SQL.squish)
      UPDATE dns_server_zones
      SET last_transfer_log_id = #{bogus_id},
          last_transfer_at = #{connection.quote(bogus_at)},
          last_transfer_status = 0,
          last_transfer_primary_addr = '192.0.2.1',
          last_transfer_serial = 0
      WHERE id = #{server_zone_id}
    SQL

    migrate_up!

    expect(row_count(:dns_server_zone_transfer_logs)).to eq(0)
    zone = find_row(:dns_server_zones, id: server_zone_id)
    expect(zone.fetch('last_transfer_log_id')).to be_nil
    expect(zone.fetch('last_transfer_at')).to be_nil
    expect(zone.fetch('last_transfer_status')).to be_nil
    expect(zone.fetch('last_transfer_reason_code')).to be_nil
    expect(zone.fetch('last_transfer_reason')).to be_nil
    expect(zone.fetch('last_transfer_primary_addr')).to be_nil
    expect(zone.fetch('last_transfer_serial')).to be_nil
  end

  it 'keeps real successful transfers with serial zero' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    success_at = timestamp
    success_id = insert_transfer_log(
      server_zone_id,
      event_key: 'real-success',
      event_at: success_at,
      status: 0,
      reason_code: nil,
      reason: nil,
      primary_addr: '192.0.2.1',
      serial: 0,
      message: 'Transfer completed successfully',
      raw_message:
        "transfer of 'example.test/IN' from 192.0.2.1#53: Transfer completed: " \
        '1 messages, 5 records, 400 bytes, 0.001 secs (serial 0)',
      source_cursor: 'cursor-success'
    )
    connection.update(<<~SQL.squish)
      UPDATE dns_server_zones
      SET last_transfer_log_id = #{success_id},
          last_transfer_at = #{connection.quote(success_at)},
          last_transfer_status = 0,
          last_transfer_primary_addr = '192.0.2.1',
          last_transfer_serial = 0
      WHERE id = #{server_zone_id}
    SQL

    migrate_up!

    expect(row_count(:dns_server_zone_transfer_logs)).to eq(1)
    zone = find_row(:dns_server_zones, id: server_zone_id)
    expect(zone.fetch('last_transfer_log_id').to_i).to eq(success_id)
    expect(zone.fetch('last_transfer_status').to_i).to eq(0)
    expect(zone.fetch('last_transfer_serial').to_i).to eq(0)
  end
end
