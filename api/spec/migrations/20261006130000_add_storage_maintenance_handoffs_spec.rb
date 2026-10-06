# frozen_string_literal: true

require 'digest'
require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261006120000_add_storage_maintenance_reservations')
MigrationSpecSupport.require_migration('20261006130000_add_storage_maintenance_handoffs')

RSpec.describe AddStorageMaintenanceHandoffs do
  before do
    # Exact touched predecessor definition from the consumed core schema.
    define_schema do
      create_table :storage_freeze_controls, id: :bigint, default: nil,
                                             charset: 'utf8mb3', collation: 'utf8mb3_unicode_ci' do |t|
        t.integer :mode, default: 0, null: false
        t.bigint :epoch, default: 0, null: false, unsigned: true
        t.integer :requested_by_user_id, unsigned: true
        t.datetime :requested_at
        t.string :reason
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
        t.check_constraint 'id = 1', name: 'chk_storage_freeze_singleton'
      end
      create_table 'storage_freeze_transitions', charset: 'utf8mb3', collation: 'utf8mb3_unicode_ci' do |t|
        t.bigint 'storage_freeze_control_id', null: false
        t.integer 'prior_mode', null: false
        t.integer 'new_mode', null: false
        t.bigint 'prior_epoch', null: false, unsigned: true
        t.bigint 'new_epoch', null: false, unsigned: true
        t.integer 'actor_user_id', null: false, unsigned: true
        t.integer 'actor_user_session_id', null: false, unsigned: true
        t.string 'actor_user_login', limit: 128, null: false
        t.string 'reason', null: false
        t.datetime 'created_at', null: false
        t.index ['actor_user_id'], name: 'index_storage_freeze_transitions_on_actor_user_id'
        t.index ['actor_user_session_id'], name: 'index_storage_freeze_transitions_on_actor_user_session_id'
        t.index ['new_epoch'], name: 'index_storage_freeze_transitions_on_new_epoch', unique: true
        t.index ['storage_freeze_control_id'], name: 'index_storage_freeze_transitions_on_storage_freeze_control_id'
        t.check_constraint '`actor_user_id` > 0 and `actor_user_session_id` > 0 and char_length(trim(`actor_user_login`)) between 1 and 128', name: 'chk_storage_freeze_transition_actor'
        t.check_constraint '`new_epoch` = `prior_epoch` + 1', name: 'chk_storage_freeze_transition_epoch'
        t.check_constraint '`prior_mode` in (0,1) and `new_mode` in (0,1) and `prior_mode` <> `new_mode`', name: 'chk_storage_freeze_transition_modes'
        t.check_constraint 'char_length(trim(`reason`)) between 1 and 255', name: 'chk_storage_freeze_transition_reason'
      end
      add_foreign_key :storage_freeze_transitions, :storage_freeze_controls
    end
    insert_row(:storage_freeze_controls, id: 1, mode: 1, epoch: 7,
                                         reason: 'retained freeze', created_at: timestamp, updated_at: timestamp)
    insert_row(:storage_freeze_transitions, id: 3, storage_freeze_control_id: 1,
                                            prior_mode: 0, new_mode: 1, prior_epoch: 6, new_epoch: 7, actor_user_id: 7,
                                            actor_user_session_id: 9, actor_user_login: 'admin', reason: 'retained freeze', created_at: timestamp)
    migrate_up!(AddStorageMaintenanceReservations)
  end

  def acquisition
    scope = '{"pools":[]}'
    {
      request_id: '00000000-0000-0000-0000-000000000001', record_contract: 1,
      requested_profile: 'manual_storage_only_v1', state: 'reserved', revision: 1,
      freeze_epoch: 7, requested_scope_json: scope, requested_scope_digest: Digest::SHA256.hexdigest(scope),
      acquired_by_user_id: 7, acquired_by_user_session_id: 9, acquired_by_user_login: 'admin',
      acquisition_reason: 'API-only reservation', acquired_at: timestamp
    }
  end

  def handoff
    acquisition.merge(record_contract: 2, state: 'handoff_pending', revision: 2,
                      handed_off_by_user_id: 8, handed_off_by_user_session_id: 10,
                      handed_off_by_user_login: 'accepting-admin', handoff_reason: 'prospective responsibility',
                      handed_off_at: timestamp)
  end

  def maintenance_run_indexes
    connection.indexes(:storage_maintenance_runs).map do |index|
      [
        index.table, index.name, index.unique, index.columns, index.lengths,
        index.orders, index.opclasses, index.where, index.type, index.using,
        index.include, index.nulls_not_distinct, index.comment, index.valid,
        index.enabled
      ]
    end
  end

  it 'preserves consumed reservation rows, pointer, acquisition audit and freeze history' do
    id = insert_row(:storage_maintenance_runs, acquisition)
    insert_row(:storage_maintenance_runs,
               acquisition.merge(request_id: '00000000-0000-0000-0000-000000000002',
                                 state: 'abandoned', revision: 2, abandoned_by_user_id: 8,
                                 abandoned_by_user_session_id: 10, abandoned_by_user_login: 'other-admin',
                                 abandonment_reason: 'unused reservation', abandoned_at: timestamp))
    connection.execute("UPDATE storage_freeze_controls SET active_maintenance_run_id = #{id} WHERE id = 1")
    before = rows(:storage_maintenance_runs)
    control = rows(:storage_freeze_controls)
    history = rows(:storage_freeze_transitions)
    indexes = maintenance_run_indexes
    fk = connection.foreign_keys(:storage_freeze_controls).sole
    migrate_up!
    expect(rows(:storage_maintenance_runs).map { |row| row.except(*described_class::HANDOFF_COLUMNS) }).to eq(before)
    expect(rows(:storage_maintenance_runs).map { |row| row.slice(*described_class::HANDOFF_COLUMNS).values })
      .to all(eq([nil] * 5))
    expect(rows(:storage_freeze_controls)).to eq(control)
    expect(rows(:storage_freeze_transitions)).to eq(history)
    expect(maintenance_run_indexes).to eq(indexes)
    expect(connection.foreign_keys(:storage_freeze_controls).sole).to eq(fk)
    expect { connection.execute("DELETE FROM storage_maintenance_runs WHERE id = #{id}") }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'requires all five handoff audit values and retains UUID uniqueness' do
    migrate_up!
    described_class::HANDOFF_COLUMNS.each do |field|
      expect { insert_row(:storage_maintenance_runs, handoff.merge(field.to_sym => nil)) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
    [[:handed_off_by_user_id, 0], [:handed_off_by_user_session_id, 0],
     [:handed_off_by_user_login, ' '], [:handoff_reason, ' ']].each do |field, value|
      expect { insert_row(:storage_maintenance_runs, handoff.merge(field => value)) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
    insert_row(:storage_maintenance_runs, handoff)
    expect { insert_row(:storage_maintenance_runs, handoff) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(find_row(:storage_maintenance_runs, request_id: handoff[:request_id]))
      .to include('record_contract' => 2, 'state' => 'handoff_pending', 'revision' => 2)
  end

  it 'rejects unknown tuples and audit from the other supported contract' do
    migrate_up!
    [{ record_contract: 2 }, { record_contract: 3 }, { state: 'handoff_pending', revision: 2 },
     { revision: 2 }, { state: 'RESERVED' }, { requested_profile: 'MANUAL_STORAGE_ONLY_V1' },
     { handoff_reason: 'unexpected' }].each do |attrs|
      expect { insert_row(:storage_maintenance_runs, acquisition.merge(attrs)) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
    [{ record_contract: 1 }, { revision: 1 }, { state: 'reserved' }, { state: 'HANDOFF_PENDING' },
     { abandoned_at: timestamp }].each do |attrs|
      expect { insert_row(:storage_maintenance_runs, handoff.merge(attrs)) }
        .to raise_error(ActiveRecord::StatementInvalid)
    end
    expect(row_count(:storage_maintenance_runs)).to eq(0)
  end

  it 'refuses unsupported predecessor contracts before any additive DDL' do
    insert_row(:storage_maintenance_runs, acquisition.merge(record_contract: 3))
    before = rows(:storage_maintenance_runs)
    expect { migrate_up! }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(described_class::HANDOFF_COLUMNS.map { |field| column_exists?(:storage_maintenance_runs, field) })
      .to eq([false] * 5)
    expect(rows(:storage_maintenance_runs)).to eq(before)
  end

  it 'refuses unknown or differently cased predecessor profiles and states without normalization' do
    [{ requested_profile: 'unknown' }, { requested_profile: 'MANUAL_STORAGE_ONLY_V1' },
     { state: 'RESERVED' }].each_with_index do |attrs, index|
      id = insert_row(:storage_maintenance_runs,
                      acquisition.merge(request_id: format('00000000-0000-0000-0000-%012d', index + 1)).merge(attrs))
      before = rows(:storage_maintenance_runs)
      expect { migrate_up! }.to raise_error(ActiveRecord::IrreversibleMigration)
      expect(column_exists?(:storage_maintenance_runs, :handed_off_at)).to be(false)
      expect(rows(:storage_maintenance_runs)).to eq(before)
      connection.execute("DELETE FROM storage_maintenance_runs WHERE id = #{id}")
    end
  end

  it 'refuses down before DDL for a handed-off owner, preserving its complete audit' do
    migrate_up!
    id = insert_row(:storage_maintenance_runs, handoff)
    connection.execute("UPDATE storage_freeze_controls SET active_maintenance_run_id = #{id} WHERE id = 1")
    before = rows(:storage_maintenance_runs)
    control = rows(:storage_freeze_controls)
    expect { migrate_down! }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(rows(:storage_maintenance_runs)).to eq(before)
    expect(rows(:storage_freeze_controls)).to eq(control)
    expect(described_class::HANDOFF_COLUMNS.map { |field| column_exists?(:storage_maintenance_runs, field) })
      .to eq([true] * 5)
  end

  it 'refuses unknown or stray-audit content before down DDL' do
    migrate_up!
    id = insert_row(:storage_maintenance_runs, acquisition)
    # Privileged corruption is confined to this owned disposable table.
    connection.remove_check_constraint(:storage_maintenance_runs, name: described_class::TERMINAL_CONSTRAINT)
    ['record_contract = 3', "record_contract = 1, handoff_reason = 'unexpected'"].each do |assignment|
      connection.execute("UPDATE storage_maintenance_runs SET #{assignment} WHERE id = #{id}")
      before = rows(:storage_maintenance_runs)
      expect { migrate_down! }.to raise_error(ActiveRecord::IrreversibleMigration)
      expect(rows(:storage_maintenance_runs)).to eq(before)
      expect(column_exists?(:storage_maintenance_runs, :handed_off_at)).to be(true)
    end
  end

  it 'restores the exact predecessor for untouched contract one rows without losing audit' do
    id = insert_row(:storage_maintenance_runs, acquisition)
    connection.execute("UPDATE storage_freeze_controls SET active_maintenance_run_id = #{id} WHERE id = 1")
    before = rows(:storage_maintenance_runs)
    control = rows(:storage_freeze_controls)
    constraints = connection.check_constraints(:storage_maintenance_runs)
    migrate_up!
    migrate_down!
    expect(rows(:storage_maintenance_runs)).to eq(before)
    expect(rows(:storage_freeze_controls)).to eq(control)
    expect(connection.check_constraints(:storage_maintenance_runs)).to eq(constraints)
    expect(described_class::HANDOFF_COLUMNS.map { |field| column_exists?(:storage_maintenance_runs, field) })
      .to eq([false] * 5)
    expect { connection.execute("DELETE FROM storage_maintenance_runs WHERE id = #{id}") }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end
end
