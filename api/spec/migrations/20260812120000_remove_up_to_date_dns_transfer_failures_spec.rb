# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260812120000_remove_up_to_date_dns_transfer_failures')

RSpec.describe RemoveUpToDateDnsTransferFailures do
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

  def insert_server_zone
    insert_row(
      :dns_server_zones,
      {
        last_transfer_log_id: nil,
        last_transfer_at: nil,
        last_transfer_status: nil,
        last_transfer_reason_code: nil,
        last_transfer_reason: nil,
        last_transfer_primary_addr: nil,
        last_transfer_serial: nil
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

  def insert_success(server_zone_id, event_key:, event_at:, serial: 2_026_080_601)
    insert_transfer_log(
      server_zone_id,
      event_key:,
      event_at:,
      status: 0,
      reason_code: nil,
      reason: nil,
      primary_addr: '192.0.2.1',
      serial:,
      message: 'Transfer completed successfully',
      raw_message:
        "transfer of 'example.test/IN' from 192.0.2.1#53: Transfer completed: " \
        "0 messages, 1 records, 0 bytes, 0.005 secs (0 bytes/sec) (serial #{serial})",
      source_cursor: "cursor-#{event_key}"
    )
  end

  def insert_failure(server_zone_id, event_key:, event_at:)
    insert_transfer_log(
      server_zone_id,
      event_key:,
      event_at:,
      status: 1,
      reason_code: 'timeout',
      reason: 'The primary DNS server did not respond in time',
      primary_addr: '192.0.2.1',
      serial: nil,
      message: 'timed out',
      raw_message:
        "transfer of 'example.test/IN' from 192.0.2.1#53: Transfer status: timed out",
      source_cursor: "cursor-#{event_key}"
    )
  end

  def insert_synthetic_failure(
    server_zone_id,
    event_key:,
    event_at:,
    message: 'up to date',
    raw_message: nil
  )
    insert_transfer_log(
      server_zone_id,
      event_key:,
      event_at:,
      status: 1,
      reason_code: 'unknown',
      reason: 'The transfer failed',
      primary_addr: '192.0.2.1',
      serial: nil,
      message:,
      raw_message: raw_message ||
        "0x7b91dee53000: transfer of 'example.test/IN' from 192.0.2.1#53: " \
        'Transfer status: up to date',
      source_cursor: "cursor-#{event_key}"
    )
  end

  def point_server_zone_at(server_zone_id, transfer_log_id)
    log = find_row(:dns_server_zone_transfer_logs, id: transfer_log_id)

    connection.update(<<~SQL.squish)
      UPDATE dns_server_zones
      SET last_transfer_log_id = #{transfer_log_id},
          last_transfer_at = #{connection.quote(log.fetch('event_at'))},
          last_transfer_status = #{connection.quote(log.fetch('status'))},
          last_transfer_reason_code = #{connection.quote(log['reason_code'])},
          last_transfer_reason = #{connection.quote(log['reason'])},
          last_transfer_primary_addr = #{connection.quote(log['primary_addr'])},
          last_transfer_serial = #{connection.quote(log['serial'])}
      WHERE id = #{server_zone_id}
    SQL
  end

  it 'removes a synthetic failure without changing the following success' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    event_at = timestamp
    synthetic_id = insert_synthetic_failure(
      server_zone_id,
      event_key: 'synthetic',
      event_at:
    )
    success_id = insert_success(
      server_zone_id,
      event_key: 'success',
      event_at:
    )
    point_server_zone_at(server_zone_id, success_id)

    migrate_up!

    expect(find_rows(:dns_server_zone_transfer_logs).map { |row| row.fetch('id').to_i }).to eq([success_id])
    expect(find_rows(:dns_server_zone_transfer_logs, { id: synthetic_id })).to be_empty

    zone = find_row(:dns_server_zones, id: server_zone_id)
    expect(zone.fetch('last_transfer_log_id').to_i).to eq(success_id)
    expect(zone.fetch('last_transfer_status').to_i).to eq(0)
    expect(zone.fetch('last_transfer_reason_code')).to be_nil
    expect(zone.fetch('last_transfer_reason')).to be_nil
    expect(zone.fetch('last_transfer_primary_addr')).to eq('192.0.2.1')
    expect(zone.fetch('last_transfer_serial').to_i).to eq(2_026_080_601)
  end

  it 'repairs a same-second synthetic latest state to the successful completion' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    event_at = timestamp
    success_id = insert_success(
      server_zone_id,
      event_key: 'success',
      event_at:
    )
    synthetic_id = insert_synthetic_failure(
      server_zone_id,
      event_key: 'synthetic',
      event_at:
    )
    point_server_zone_at(server_zone_id, synthetic_id)

    migrate_up!

    zone = find_row(:dns_server_zones, id: server_zone_id)
    expect(zone.fetch('last_transfer_log_id').to_i).to eq(success_id)
    expect(zone.fetch('last_transfer_status').to_i).to eq(0)
    expect(zone.fetch('last_transfer_reason_code')).to be_nil
    expect(zone.fetch('last_transfer_reason')).to be_nil
    expect(zone.fetch('last_transfer_serial').to_i).to eq(2_026_080_601)
  end

  it 'restores the newest genuine failure when removing synthetic latest state' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    failure_id = insert_failure(
      server_zone_id,
      event_key: 'failure',
      event_at: timestamp
    )
    synthetic_id = insert_synthetic_failure(
      server_zone_id,
      event_key: 'synthetic',
      event_at: timestamp + 1.minute
    )
    point_server_zone_at(server_zone_id, synthetic_id)

    migrate_up!

    zone = find_row(:dns_server_zones, id: server_zone_id)
    expect(zone.fetch('last_transfer_log_id').to_i).to eq(failure_id)
    expect(zone.fetch('last_transfer_status').to_i).to eq(1)
    expect(zone.fetch('last_transfer_reason_code')).to eq('timeout')
    expect(zone.fetch('last_transfer_reason')).to eq('The primary DNS server did not respond in time')
    expect(zone.fetch('last_transfer_primary_addr')).to eq('192.0.2.1')
    expect(zone.fetch('last_transfer_serial')).to be_nil
  end

  it 'clears latest transfer state when only synthetic failures remain' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    synthetic_id = insert_synthetic_failure(
      server_zone_id,
      event_key: 'synthetic',
      event_at: timestamp
    )
    point_server_zone_at(server_zone_id, synthetic_id)

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

  it 'keeps nearby legitimate unknown failures' do
    define_transfer_log_schema
    server_zone_id = insert_server_zone
    unknown_id = insert_transfer_log(
      server_zone_id,
      event_key: 'unknown',
      event_at: timestamp,
      status: 1,
      reason_code: 'unknown',
      reason: 'The transfer failed',
      primary_addr: '192.0.2.1',
      serial: nil,
      message: 'unexpected EOF',
      raw_message:
        "transfer of 'example.test/IN' from 192.0.2.1#53: Transfer status: unexpected EOF",
      source_cursor: 'cursor-unknown'
    )
    mismatched_raw_id = insert_synthetic_failure(
      server_zone_id,
      event_key: 'mismatched-raw',
      event_at: timestamp + 1.minute,
      raw_message:
        "transfer of 'example.test/IN' from 192.0.2.1#53: Transfer status: unexpected EOF"
    )
    insert_synthetic_failure(
      server_zone_id,
      event_key: 'uppercase-synthetic',
      event_at: timestamp + 2.minutes,
      message: 'UP TO DATE',
      raw_message:
        "0x7b91dee53000: TRANSFER OF 'example.test/IN' FROM 192.0.2.1#53: " \
        'TRANSFER STATUS: UP TO DATE'
    )

    migrate_up!

    expect(find_rows(:dns_server_zone_transfer_logs).map { |row| row.fetch('id').to_i }).to eq(
      [unknown_id, mismatched_raw_id]
    )
  end
end
