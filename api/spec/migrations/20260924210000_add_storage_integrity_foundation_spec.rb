# frozen_string_literal: true

require 'digest'
require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260924210000_add_storage_integrity_foundation')

RSpec.describe AddStorageIntegrityFoundation do
  before do
    define_schema do
      %i[nodes pools dataset_in_pools dataset_trees branches
         snapshot_in_pool_clones snapshot_in_pools snapshot_in_pool_in_branches
         transactions transaction_chains].each do |name|
        create_table name, id: { type: :integer, unsigned: true }
      end
      create_table :transaction_confirmations, id: { type: :integer, unsigned: true } do |t|
        t.integer :done
        t.integer :transaction_id, unsigned: true
      end
    end
  end

  it 'adds catalog identity, retained audit and receipt tables with real FKs' do
    migrate_up!

    expect(column_exists?(:pools, :zpool_guid)).to be(true)
    expect(column_exists?(:snapshot_in_pools, :zfs_owner_fs_guid)).to be(true)
    expect(column_exists?(:snapshot_in_pool_in_branches, :zfs_path)).to be(true)
    expect(table_exists?(:storage_reconciliation_actions)).to be(false)
    expect(table_exists?(:storage_reconciliation_decisions)).to be(false)
    expect(table_exists?(:storage_freeze_transitions)).to be(true)
    expect(table_exists?(:storage_observer_catch_up_audits)).to be(true)
    expect(table_exists?(:storage_mutation_intent_scopes)).to be(true)
    expect(table_exists?(:storage_mutation_target_observations)).to be(true)

    fs_foreign_keys = connection.foreign_keys(:storage_filesystem_identities)
                                .map(&:column)
    expect(fs_foreign_keys).to include(
      'node_id', 'owner_pool_id', 'dataset_in_pool_id',
      'origin_snapshot_in_pool_id', 'origin_snapshot_in_pool_in_branch_id'
    )
    target_foreign_keys = connection.foreign_keys(:storage_mutation_targets)
                                    .map(&:column)
    expect(target_foreign_keys).to include(
      'storage_mutation_intent_scope_id', 'storage_filesystem_identity_id'
    )

    unique_path = connection.indexes(:storage_filesystem_identities).find do |index|
      index.name == 'idx_storage_fs_node_path_digest'
    end
    expect(unique_path.columns).to eq(%w[node_id path_digest])
    expect(unique_path.unique).to be(true)
    expect(row_count(:storage_freeze_controls)).to eq(1)
    expect(find_row(:storage_freeze_controls, id: 1).fetch('mode')).to eq(0)
    expect(column(:storage_mutation_intents, :settlement_provenance).limit).to eq(32)
    expect(column(:storage_mutation_attempts, :strict_signed_input_digest).limit).to eq(64)
    expect(column_exists?(:storage_freeze_transitions, :operator_uid)).to be(false)
    expect(column_exists?(:storage_observer_catch_up_audits, :actor_source)).to be(false)
    expect(connection.indexes(:transaction_confirmations).map(&:name))
      .to include('idx_transaction_confirmations_done_transaction')
    expect do
      insert_row(:storage_freeze_controls,
                 id: 2, mode: 0, epoch: 0,
                 created_at: timestamp, updated_at: timestamp)
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'rejects duplicate node paths and unresolved FK references' do
    migrate_up!
    insert_row(:nodes, id: 1)
    insert_row(:pools, id: 10)
    insert_row(:pools, id: 11)
    insert_row(:dataset_in_pools, id: 20)

    path = 'tank/managed'
    attrs = {
      node_id: 1, pool_id: 10, owner_pool_id: 10, zfs_path: path,
      path_digest: Digest::SHA256.hexdigest(path), physical_presence: 1,
      zfs_guid: 42, created_at: timestamp, updated_at: timestamp
    }
    insert_row(:storage_filesystem_identities, attrs)

    expect do
      insert_row(:storage_filesystem_identities, attrs.merge(pool_id: 11, owner_pool_id: 11))
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect do
      insert_row(:storage_filesystem_identities,
                 node_id: 1, pool_id: 10, dataset_in_pool_id: 20,
                 origin_snapshot_in_pool_id: 999,
                 created_at: timestamp, updated_at: timestamp)
    end.to raise_error(ActiveRecord::InvalidForeignKey)
    expect do
      insert_row(:storage_filesystem_identities,
                 node_id: 1, pool_id: 10, dataset_in_pool_id: 20,
                 zfs_path: 'tank/other',
                 created_at: timestamp, updated_at: timestamp)
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'requires API actor evidence and paired strict attempt provenance' do
    migrate_up!
    audit = {
      storage_freeze_control_id: 1, prior_mode: 0, new_mode: 1,
      prior_epoch: 0, new_epoch: 1, actor_user_id: 7,
      actor_user_session_id: 9, actor_user_login: 'admin',
      reason: 'maintenance', created_at: timestamp
    }
    insert_row(:storage_freeze_transitions, audit)
    expect do
      insert_row(:storage_freeze_transitions,
                 audit.merge(new_epoch: 2, actor_user_login: '  '))
    end.to raise_error(ActiveRecord::StatementInvalid)

    catch_up = {
      request_id: 'a' * 36, event_type: 0,
      actor_user_id: 7, actor_user_session_id: 9,
      actor_user_login: 'admin', reason: 'review old results',
      freeze_epoch: 1, after_chain_id: 0, page_limit: 100,
      created_at: timestamp
    }
    insert_row(:storage_observer_catch_up_audits, catch_up)
    expect do
      insert_row(:storage_observer_catch_up_audits,
                 catch_up.merge(request_id: 'b' * 36, actor_user_login: ' '))
    end.to raise_error(ActiveRecord::StatementInvalid)

    insert_row(:nodes, id: 1)
    insert_row(:storage_mutation_intents,
               id: 1, token: 'token', node_id: 1, node_catalog_id: 1,
               kind: 'observer', protocol_version: 1, manifest_digest: 'a' * 64,
               created_at: timestamp, updated_at: timestamp)
    attempt = {
      storage_mutation_intent_id: 1, command_key: '5204',
      direction: 0, attempt_number: 1, state: 0,
      created_at: timestamp, updated_at: timestamp
    }
    insert_row(:storage_mutation_attempts, attempt)
    expect do
      insert_row(:storage_mutation_attempts,
                 attempt.merge(attempt_number: 2, strict_dispatch_registry_version: 4))
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'reverses the foundation without altering baseline tables' do
    migrate_up!
    migrate_down!

    expect(table_exists?(:storage_integrity_scopes)).to be(false)
    expect(table_exists?(:storage_mutation_target_observations)).to be(false)
    expect(table_exists?(:storage_filesystem_identities)).to be(false)
    expect(table_exists?(:storage_freeze_transitions)).to be(false)
    expect(table_exists?(:storage_observer_catch_up_audits)).to be(false)
    expect(connection.indexes(:transaction_confirmations).map(&:name))
      .not_to include('idx_transaction_confirmations_done_transaction')
    expect(column_exists?(:snapshot_in_pools, :zfs_guid)).to be(false)
    expect(column_exists?(:snapshot_in_pool_in_branches, :storage_observation_run_id)).to be(false)
    expect(column_exists?(:pools, :zpool_guid)).to be(false)
    expect(table_exists?(:pools)).to be(true)
  end
end
