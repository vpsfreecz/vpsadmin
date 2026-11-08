# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261108120000_add_dns_primary_transfer_states')

RSpec.describe AddDnsPrimaryTransferStates do
  def define_transfer_schema
    define_schema do
      create_table :dns_zones do |t|
        t.boolean :enabled, default: true, null: false
        t.integer :zone_source, default: 0, null: false
      end

      create_table :dns_server_zones do |t|
        t.datetime :last_transfer_at
        t.integer :last_transfer_status
        t.string :last_transfer_reason_code, limit: 40
        t.string :last_transfer_reason, limit: 255
        t.string :last_transfer_primary_addr, limit: 46
        t.integer :last_transfer_serial, unsigned: true
        t.bigint :last_transfer_log_id
      end

      create_table :dns_zone_transfers

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

  def insert_log(zone_id)
    now = timestamp
    insert_row(
      :dns_server_zone_transfer_logs,
      dns_server_zone_id: zone_id,
      event_key: SecureRandom.hex(32),
      event_at: now,
      status: 1,
      reason_code: 'refused',
      reason: 'Legacy failure',
      primary_addr: '192.0.2.1',
      serial: nil,
      message: 'REFUSED',
      raw_message: 'Transfer status: REFUSED',
      source_cursor: 'cursor',
      created_at: now,
      updated_at: now
    )
  end

  it 'creates a fresh generation and the M:N probe state schema' do
    define_transfer_schema
    external_zone_id = insert_row(:dns_zones, enabled: true, zone_source: 1)
    disabled_zone_id = insert_row(:dns_zones, enabled: false, zone_source: 1)

    migrate_up!

    external = find_row(:dns_zones, id: external_zone_id)
    disabled = find_row(:dns_zones, id: disabled_zone_id)
    expect(external.fetch('primary_transfer_tracking_started_at')).not_to be_nil
    expect(external.fetch('primary_transfer_generation')).to match(/\A[0-9a-f-]{36}\z/i)
    expect(disabled.fetch('primary_transfer_tracking_started_at')).to be_nil
    expect(disabled.fetch('primary_transfer_generation')).to be_nil

    expect(column_exists?(:dns_server_zone_transfer_logs, :dns_zone_transfer_id)).to be(true)
    attempt_kind = connection.columns(:dns_server_zone_transfer_logs).find do |column|
      column.name == 'attempt_kind'
    end
    expect(attempt_kind).to be_present
    expect(attempt_kind.null).to be(true)
    expect(column_exists?(:dns_server_zone_transfer_logs, :primary_serial)).to be(true)
    expect(column_exists?(:dns_server_zone_transfer_logs, :secondary_serial)).to be(true)
    expect(table_exists?(:dns_server_zone_primary_transfer_states)).to be(true)
    expect(column_exists?(:dns_server_zone_primary_transfer_states, :configuration_generation)).to be(true)
    expect(column_exists?(:dns_server_zone_primary_transfer_states, :alert_eligible_at)).to be(true)
    expect(index_exists?(:dns_server_zone_primary_transfer_states, 'idx_dns_primary_transfer_states_on_path')).to be(true)

    log_foreign_keys = connection.foreign_keys(:dns_server_zone_transfer_logs).index_by(&:column)
    expect(log_foreign_keys.fetch('dns_server_zone_id')).to have_attributes(
      to_table: 'dns_server_zones',
      options: include(on_delete: :cascade)
    )
    expect(log_foreign_keys.fetch('dns_zone_transfer_id')).to have_attributes(
      to_table: 'dns_zone_transfers',
      options: include(on_delete: :nullify)
    )

    state_foreign_keys =
      connection.foreign_keys(:dns_server_zone_primary_transfer_states).index_by(&:column)
    expect(state_foreign_keys.fetch('dns_server_zone_id')).to have_attributes(
      to_table: 'dns_server_zones',
      options: include(on_delete: :cascade)
    )
    expect(state_foreign_keys.fetch('dns_zone_transfer_id')).to have_attributes(
      to_table: 'dns_zone_transfers',
      options: include(on_delete: :cascade)
    )
    expect(state_foreign_keys.fetch('last_transfer_log_id')).to have_attributes(
      to_table: 'dns_server_zone_transfer_logs',
      options: include(on_delete: :nullify)
    )
  end

  it 'preserves old transfer history and cached latest fields as legacy audit' do
    define_transfer_schema
    zone_id = insert_row(:dns_server_zones, {})
    log_id = insert_log(zone_id)
    connection.update(<<~SQL.squish)
      UPDATE dns_server_zones
      SET last_transfer_log_id = #{log_id},
          last_transfer_at = CURRENT_TIMESTAMP,
          last_transfer_status = 1,
          last_transfer_reason_code = 'refused',
          last_transfer_reason = 'Legacy failure',
          last_transfer_primary_addr = '192.0.2.1'
      WHERE id = #{zone_id}
    SQL

    migrate_up!

    expect(row_count(:dns_server_zone_transfer_logs)).to eq(1)
    log = find_row(:dns_server_zone_transfer_logs, id: log_id)
    expect(log.fetch('attempt_kind')).to eq(6)
    expect(log.fetch('dns_zone_transfer_id')).to be_nil
    expect(log.fetch('raw_message')).to eq('Transfer status: REFUSED')
    zone = find_row(:dns_server_zones, id: zone_id)
    expect(zone.fetch('last_transfer_log_id')).to eq(log_id)
    expect(zone.fetch('last_transfer_status')).to eq(1)
    expect(zone.fetch('last_transfer_reason_code')).to eq('refused')
    expect(row_count(:dns_server_zone_primary_transfer_states)).to eq(0)
  end

  it 'refuses orphan audit content before altering schema' do
    define_transfer_schema
    log_id = insert_log(999_999)

    expect { migrate_up! }.to raise_error(ActiveRecord::MigrationError, /orphan transfer log IDs=#{log_id}/)
    expect(column_exists?(:dns_zones, :primary_transfer_generation)).to be(false)
    expect(row_count(:dns_server_zone_transfer_logs)).to eq(1)
  end

  it 'refuses invalid latest pointers without deleting history' do
    define_transfer_schema
    zone_id = insert_row(:dns_server_zones, last_transfer_log_id: 999_999)

    expect { migrate_up! }.to raise_error(ActiveRecord::MigrationError, /server-zone IDs=#{zone_id}/)
    expect(column_exists?(:dns_zones, :primary_transfer_generation)).to be(false)
  end

  it 'retains additive schema on rollback to preserve new audit' do
    define_transfer_schema
    migrate_up!

    expect { migrate_down! }.to raise_error(
      ActiveRecord::IrreversibleMigration,
      /preserve audit history/
    )
  end
end
