# frozen_string_literal: true

require 'digest'
require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20261006120000_add_storage_maintenance_reservations')

RSpec.describe AddStorageMaintenanceReservations do
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

  it 'adds no inferred ownership and preserves predecessor control, rows and indexes' do
    before = find_row(:storage_freeze_controls, id: 1)
    migrate_up!
    after = find_row(:storage_freeze_controls, id: 1)
    expect(after.except('active_maintenance_run_id')).to eq(before)
    expect(after['active_maintenance_run_id']).to be_nil
    expect(row_count(:storage_maintenance_runs)).to eq(0)
    expect(find_row(:storage_freeze_transitions, id: 3)['new_epoch']).to eq(7)
    expect(index_exists?(:storage_freeze_transitions, 'index_storage_freeze_transitions_on_new_epoch')).to be(true)
    fk = connection.foreign_keys(:storage_freeze_controls).sole
    expect(fk.column).to eq('active_maintenance_run_id')
    expect(fk.to_table).to eq('storage_maintenance_runs')
  end

  it 'enforces UUID uniqueness and complete scalar acquisition audit' do
    migrate_up!
    insert_row(:storage_maintenance_runs, acquisition)
    expect { insert_row(:storage_maintenance_runs, acquisition) }.to raise_error(ActiveRecord::RecordNotUnique)
    expect { insert_row(:storage_maintenance_runs, acquisition.merge(request_id: 'invalid')) }
      .to raise_error(ActiveRecord::StatementInvalid)
    expect do
      insert_row(:storage_maintenance_runs,
                 acquisition.merge(request_id: '00000000-0000-0000-0000-000000000002', acquired_by_user_id: 0))
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'enforces supported state/revision pairs and a complete terminal audit group' do
    migrate_up!
    expect { insert_row(:storage_maintenance_runs, acquisition.merge(state: 'abandoned', revision: 2)) }
      .to raise_error(ActiveRecord::StatementInvalid)
    expect { insert_row(:storage_maintenance_runs, acquisition.merge(revision: 2)) }
      .to raise_error(ActiveRecord::StatementInvalid)
    expect { insert_row(:storage_maintenance_runs, acquisition.merge(abandoned_at: timestamp)) }
      .to raise_error(ActiveRecord::StatementInvalid)
    insert_row(:storage_maintenance_runs,
               acquisition.merge(state: 'abandoned', revision: 2, abandoned_by_user_id: 8,
                                 abandoned_by_user_session_id: 10, abandoned_by_user_login: 'other-admin',
                                 abandonment_reason: 'unused reservation', abandoned_at: timestamp))
    expect(row_count(:storage_maintenance_runs)).to eq(1)
  end

  it 'restricts pointer deletion and refuses missing owner references' do
    migrate_up!
    id = insert_row(:storage_maintenance_runs, acquisition)
    connection.execute("UPDATE storage_freeze_controls SET active_maintenance_run_id = #{id} WHERE id = 1")
    expect { connection.execute("DELETE FROM storage_maintenance_runs WHERE id = #{id}") }
      .to raise_error(ActiveRecord::InvalidForeignKey)
    expect { connection.execute('UPDATE storage_freeze_controls SET active_maintenance_run_id = 999 WHERE id = 1') }
      .to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it 'refuses downgrade before any DDL once audit exists, even after abandonment' do
    migrate_up!
    insert_row(:storage_maintenance_runs,
               acquisition.merge(state: 'abandoned', revision: 2, abandoned_by_user_id: 8,
                                 abandoned_by_user_session_id: 10, abandoned_by_user_login: 'other-admin',
                                 abandonment_reason: 'unused reservation', abandoned_at: timestamp))
    expect { migrate_down! }.to raise_error(ActiveRecord::IrreversibleMigration)
    expect(column_exists?(:storage_freeze_controls, :active_maintenance_run_id)).to be(true)
    expect(row_count(:storage_maintenance_runs)).to eq(1)
  end

  it 'reverses an unused additive schema without changing the frozen predecessor' do
    before = find_row(:storage_freeze_controls, id: 1)
    migrate_up!
    migrate_down!
    expect(find_row(:storage_freeze_controls, id: 1)).to eq(before)
    expect(table_exists?(:storage_maintenance_runs)).to be(false)
    expect(index_exists?(:storage_freeze_transitions, 'index_storage_freeze_transitions_on_new_epoch')).to be(true)
    expect(find_row(:storage_freeze_transitions, id: 3)['new_epoch']).to eq(7)
  end
end
