class AddStorageIntegrityFoundation < ActiveRecord::Migration[8.1]
  def change
    add_snapshot_identity(:snapshot_in_pools)
    add_snapshot_identity(:snapshot_in_pool_in_branches)
    add_column :pools, :zpool_guid, :decimal, precision: 20, scale: 0

    create_table :storage_integrity_scopes do |t|
      t.integer :pool_id, unsigned: true
      t.integer :pool_catalog_id, null: false, unsigned: true
      t.integer :dataset_in_pool_id, unsigned: true
      t.integer :dataset_in_pool_catalog_id, unsigned: true
      t.string :scope_key, null: false, limit: 100, collation: 'utf8mb3_bin'
      t.integer :state, null: false, default: 0
      t.bigint :mutation_epoch, null: false, default: 0, unsigned: true
      t.integer :validator_version
      t.string :blocker_code, limit: 100
      t.timestamps
    end
    add_index :storage_integrity_scopes, :scope_key, unique: true
    add_index :storage_integrity_scopes, %i[pool_id dataset_in_pool_id],
              name: 'idx_storage_scopes_pool_dip'
    add_index :storage_integrity_scopes, :dataset_in_pool_id,
              name: 'idx_storage_scopes_dip'
    add_check_constraint :storage_integrity_scopes,
                         '(dataset_in_pool_catalog_id IS NULL AND ' \
                         "scope_key = CONCAT('pool:', pool_catalog_id)) OR " \
                         '(dataset_in_pool_catalog_id IS NOT NULL AND ' \
                         "scope_key = CONCAT('dip:', dataset_in_pool_catalog_id))",
                         name: 'chk_storage_scope_key'
    add_check_constraint :storage_integrity_scopes, 'state IN (0, 1, 2)',
                         name: 'chk_storage_scope_state'
    add_foreign_key :storage_integrity_scopes, :pools, on_delete: :nullify
    add_foreign_key :storage_integrity_scopes, :dataset_in_pools, on_delete: :nullify

    create_table :storage_observation_runs do |t|
      t.bigint :storage_integrity_scope_id, null: false
      t.integer :collector_version, null: false
      t.bigint :mutation_epoch, null: false, unsigned: true
      t.integer :state, null: false, default: 0
      t.datetime :db_observed_from_at
      t.datetime :db_observed_until_at
      t.datetime :node_observed_from_at
      t.datetime :node_observed_until_at
      t.string :digest, limit: 64
      t.text :counts_json
      t.string :failure_code, limit: 100
      t.timestamps
    end
    add_index :storage_observation_runs, %i[storage_integrity_scope_id id],
              name: 'idx_storage_runs_scope_id'
    add_foreign_key :storage_observation_runs, :storage_integrity_scopes,
                    on_delete: :restrict

    add_observation_reference(:snapshot_in_pools)
    add_observation_reference(:snapshot_in_pool_in_branches)

    create_table :storage_filesystem_identities do |t|
      t.integer :node_id, null: false, unsigned: true
      t.integer :pool_id, null: false, unsigned: true
      t.integer :owner_pool_id, unsigned: true
      t.integer :dataset_in_pool_id, unsigned: true
      t.integer :dataset_tree_id, unsigned: true
      t.integer :branch_id, unsigned: true
      t.integer :snapshot_in_pool_clone_id, unsigned: true
      t.integer :origin_snapshot_in_pool_id, unsigned: true
      t.integer :origin_snapshot_in_pool_in_branch_id, unsigned: true
      t.bigint :storage_observation_run_id
      t.decimal :zfs_guid, precision: 20, scale: 0
      t.string :zfs_path, limit: 1024, collation: 'utf8mb3_bin'
      t.string :path_digest, limit: 64, collation: 'utf8mb3_bin'
      t.integer :origin_state, null: false, default: 0
      t.integer :physical_presence, null: false, default: 0
      t.timestamps
    end
    %i[owner_pool_id dataset_in_pool_id dataset_tree_id branch_id
       snapshot_in_pool_clone_id].each do |owner|
      add_index :storage_filesystem_identities, owner,
                name: "idx_storage_fs_#{owner}", unique: true
    end
    add_index :storage_filesystem_identities, :pool_id
    add_index :storage_filesystem_identities, %i[node_id path_digest],
              unique: true, name: 'idx_storage_fs_node_path_digest'
    add_index :storage_filesystem_identities, :origin_snapshot_in_pool_id,
              name: 'idx_storage_fs_origin_sip'
    add_index :storage_filesystem_identities,
              :origin_snapshot_in_pool_in_branch_id,
              name: 'idx_storage_fs_origin_sipb'
    add_index :storage_filesystem_identities, :storage_observation_run_id,
              name: 'idx_storage_fs_run'
    add_check_constraint :storage_filesystem_identities,
                         '(zfs_path IS NULL AND path_digest IS NULL) OR ' \
                         '(zfs_path IS NOT NULL AND path_digest IS NOT NULL)',
                         name: 'chk_storage_fs_path_digest_pair'
    add_check_constraint :storage_filesystem_identities,
                         'physical_presence IN (0, 1, 2) AND ' \
                         '(physical_presence <> 1 OR ' \
                         '(zfs_path IS NOT NULL AND zfs_guid IS NOT NULL))',
                         name: 'chk_storage_fs_present_identity'
    add_foreign_key :storage_filesystem_identities, :pools, on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :nodes, on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :pools,
                    column: :owner_pool_id, on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :dataset_in_pools,
                    on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :dataset_trees,
                    on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :branches, on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :snapshot_in_pool_clones,
                    on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :snapshot_in_pools,
                    column: :origin_snapshot_in_pool_id, on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :snapshot_in_pool_in_branches,
                    column: :origin_snapshot_in_pool_in_branch_id, on_delete: :restrict
    add_foreign_key :storage_filesystem_identities, :storage_observation_runs,
                    on_delete: :restrict

    create_table :storage_freeze_controls, id: false do |t|
      t.primary_key :id, :bigint, auto_increment: false
      t.integer :mode, null: false, default: 0
      t.bigint :epoch, null: false, default: 0, unsigned: true
      t.integer :requested_by_user_id, unsigned: true
      t.datetime :requested_at
      t.string :reason, limit: 255
      t.timestamps
    end
    add_check_constraint :storage_freeze_controls, 'id = 1',
                         name: 'chk_storage_freeze_singleton'
    reversible do |direction|
      direction.up do
        execute <<~SQL
          INSERT INTO storage_freeze_controls
            (id, mode, epoch, created_at, updated_at)
          VALUES (1, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end

    create_table :storage_freeze_transitions do |t|
      t.bigint :storage_freeze_control_id, null: false
      t.integer :prior_mode, null: false
      t.integer :new_mode, null: false
      t.bigint :prior_epoch, null: false, unsigned: true
      t.bigint :new_epoch, null: false, unsigned: true
      t.integer :actor_user_id, null: false, unsigned: true
      t.integer :actor_user_session_id, null: false, unsigned: true
      t.string :actor_user_login, null: false, limit: 128
      t.string :reason, null: false, limit: 255
      t.datetime :created_at, null: false
    end
    add_index :storage_freeze_transitions, :new_epoch, unique: true
    add_index :storage_freeze_transitions, :storage_freeze_control_id
    add_index :storage_freeze_transitions, :actor_user_id
    add_index :storage_freeze_transitions, :actor_user_session_id
    add_foreign_key :storage_freeze_transitions, :storage_freeze_controls,
                    on_delete: :restrict
    add_check_constraint :storage_freeze_transitions,
                         'prior_mode IN (0, 1) AND new_mode IN (0, 1) AND prior_mode <> new_mode',
                         name: 'chk_storage_freeze_transition_modes'
    add_check_constraint :storage_freeze_transitions, 'new_epoch = prior_epoch + 1',
                         name: 'chk_storage_freeze_transition_epoch'
    add_check_constraint :storage_freeze_transitions,
                         'CHAR_LENGTH(TRIM(reason)) BETWEEN 1 AND 255',
                         name: 'chk_storage_freeze_transition_reason'
    add_check_constraint :storage_freeze_transitions,
                         'actor_user_id > 0 AND actor_user_session_id > 0 AND ' \
                         'CHAR_LENGTH(TRIM(actor_user_login)) BETWEEN 1 AND 128',
                         name: 'chk_storage_freeze_transition_actor'

    create_table :storage_observer_catch_up_audits do |t|
      t.string :request_id, null: false, limit: 36, collation: 'utf8mb3_bin'
      t.integer :event_type, null: false
      t.integer :actor_user_id, null: false, unsigned: true
      t.integer :actor_user_session_id, null: false, unsigned: true
      t.string :actor_user_login, null: false, limit: 128
      t.string :reason, null: false, limit: 255
      t.bigint :freeze_epoch, null: false, unsigned: true
      t.bigint :after_chain_id, null: false, unsigned: true
      t.integer :page_limit, null: false
      t.text :result_json
      t.datetime :created_at, null: false
    end
    add_index :storage_observer_catch_up_audits, %i[request_id event_type],
              unique: true, name: 'idx_storage_catch_up_request_event'
    add_index :storage_observer_catch_up_audits, %i[event_type created_at],
              name: 'idx_storage_catch_up_event_created'
    add_index :storage_observer_catch_up_audits, :actor_user_id
    add_index :storage_observer_catch_up_audits, :actor_user_session_id
    add_check_constraint :storage_observer_catch_up_audits,
                         'actor_user_id > 0 AND actor_user_session_id > 0 AND ' \
                         'CHAR_LENGTH(TRIM(actor_user_login)) BETWEEN 1 AND 128 ' \
                         'AND page_limit BETWEEN 1 AND 100',
                         name: 'chk_storage_catch_up_actor_limit'
    add_check_constraint :storage_observer_catch_up_audits,
                         'CHAR_LENGTH(TRIM(reason)) BETWEEN 1 AND 255',
                         name: 'chk_storage_catch_up_reason'
    add_check_constraint :storage_observer_catch_up_audits,
                         '(event_type = 0 AND result_json IS NULL) OR ' \
                         '(event_type = 1 AND result_json IS NOT NULL AND ' \
                         'LENGTH(result_json) <= 32768)',
                         name: 'chk_storage_catch_up_event'

    create_table :storage_mutation_intents do |t|
      t.string :token, null: false, limit: 64, collation: 'utf8mb3_bin'
      t.integer :transaction_chain_id, unsigned: true
      t.integer :transaction_id, unsigned: true
      t.integer :node_id, unsigned: true
      t.integer :node_catalog_id, null: false, unsigned: true
      t.string :kind, null: false, limit: 80
      t.integer :phase, null: false, default: 0
      t.integer :protocol_version, null: false
      t.string :manifest_digest, null: false, limit: 64
      t.datetime :settled_at
      t.string :failure_code, limit: 100
      t.string :settlement_provenance, limit: 32
      t.timestamps
    end
    add_index :storage_mutation_intents, :token, unique: true
    add_index :storage_mutation_intents, :transaction_id, unique: true
    add_index :storage_mutation_intents, :transaction_chain_id,
              name: 'idx_storage_intents_chain'
    add_index :storage_mutation_intents, %i[node_id phase],
              name: 'idx_storage_intents_node_phase'
    add_index :storage_mutation_intents, %i[phase transaction_chain_id],
              name: 'idx_storage_intents_phase_chain'
    add_foreign_key :storage_mutation_intents, :transactions,
                    on_delete: :nullify
    add_foreign_key :storage_mutation_intents, :transaction_chains,
                    on_delete: :nullify
    add_foreign_key :storage_mutation_intents, :nodes, on_delete: :nullify

    create_table :storage_mutation_intent_scopes do |t|
      t.bigint :storage_mutation_intent_id, null: false
      t.bigint :storage_integrity_scope_id, null: false
      t.bigint :expected_epoch, null: false, unsigned: true
      t.timestamps
    end
    add_index :storage_mutation_intent_scopes,
              %i[storage_mutation_intent_id storage_integrity_scope_id],
              unique: true, name: 'idx_storage_intent_scopes_unique'
    add_index :storage_mutation_intent_scopes, :storage_integrity_scope_id,
              name: 'idx_storage_intent_scopes_scope'
    add_foreign_key :storage_mutation_intent_scopes, :storage_mutation_intents,
                    on_delete: :restrict
    add_foreign_key :storage_mutation_intent_scopes, :storage_integrity_scopes,
                    on_delete: :restrict

    create_table :storage_mutation_attempts do |t|
      t.bigint :storage_mutation_intent_id, null: false
      t.string :command_key, null: false, limit: 80
      t.integer :attempt_number, null: false
      t.integer :direction, null: false
      t.integer :state, null: false, default: 0
      t.string :before_digest, limit: 64
      t.string :after_digest, limit: 64
      t.string :receipt_digest, limit: 64
      t.string :failure_code, limit: 100
      t.integer :strict_dispatch_registry_version
      t.string :strict_signed_input_digest, limit: 64
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :storage_mutation_attempts,
              %i[storage_mutation_intent_id command_key direction attempt_number],
              unique: true,
              name: 'idx_storage_attempts_identity'
    add_index :storage_mutation_attempts, %i[state storage_mutation_intent_id],
              name: 'idx_storage_attempts_state_intent'
    add_check_constraint :storage_mutation_attempts,
                         '(strict_dispatch_registry_version IS NULL AND ' \
                         'strict_signed_input_digest IS NULL) OR ' \
                         '(strict_dispatch_registry_version IS NOT NULL AND ' \
                         'strict_signed_input_digest IS NOT NULL)',
                         name: 'chk_storage_attempt_strict_provenance_pair'
    add_foreign_key :storage_mutation_attempts, :storage_mutation_intents,
                    on_delete: :restrict

    create_table :storage_mutation_targets do |t|
      t.bigint :storage_mutation_intent_id, null: false
      t.bigint :storage_mutation_intent_scope_id, null: false
      t.bigint :storage_filesystem_identity_id
      t.integer :snapshot_in_pool_id, unsigned: true
      t.integer :snapshot_in_pool_in_branch_id, unsigned: true
      t.string :catalog_kind, limit: 80
      t.bigint :catalog_id
      t.string :command_key, null: false, limit: 80
      t.integer :sequence, null: false
      t.string :kind, null: false, limit: 80
      t.string :expected_path, limit: 1024, collation: 'utf8mb3_bin'
      t.decimal :expected_guid, precision: 20, scale: 0
      t.decimal :expected_owner_fs_guid, precision: 20, scale: 0
      t.timestamps
    end
    add_index :storage_mutation_targets, :storage_mutation_intent_id,
              name: 'idx_storage_targets_intent'
    add_index :storage_mutation_targets,
              %i[storage_mutation_intent_id command_key sequence],
              name: 'idx_storage_targets_command_sequence', unique: true
    add_index :storage_mutation_targets, :storage_mutation_intent_scope_id,
              name: 'idx_storage_targets_intent_scope'
    add_index :storage_mutation_targets, :storage_filesystem_identity_id,
              name: 'idx_storage_targets_fs'
    add_index :storage_mutation_targets, :snapshot_in_pool_id,
              name: 'idx_storage_targets_sip'
    add_index :storage_mutation_targets, :snapshot_in_pool_in_branch_id,
              name: 'idx_storage_targets_sipb'
    add_check_constraint :storage_mutation_targets,
                         '(catalog_kind IS NULL AND catalog_id IS NULL) OR ' \
                         '(catalog_kind IS NOT NULL AND catalog_id IS NOT NULL)',
                         name: 'chk_storage_target_catalog_pair'
    add_foreign_key :storage_mutation_targets, :storage_mutation_intents,
                    on_delete: :restrict
    add_foreign_key :storage_mutation_targets, :storage_mutation_intent_scopes,
                    on_delete: :restrict
    add_foreign_key :storage_mutation_targets, :storage_filesystem_identities,
                    on_delete: :nullify
    add_foreign_key :storage_mutation_targets, :snapshot_in_pools,
                    on_delete: :nullify
    add_foreign_key :storage_mutation_targets, :snapshot_in_pool_in_branches,
                    on_delete: :nullify

    create_table :storage_mutation_target_observations do |t|
      t.bigint :storage_mutation_attempt_id, null: false
      t.bigint :storage_mutation_target_id, null: false
      t.integer :before_presence, null: false, default: 0
      t.integer :after_presence, null: false, default: 0
      t.string :before_path_digest, limit: 64, collation: 'utf8mb3_bin'
      t.string :after_path_digest, limit: 64, collation: 'utf8mb3_bin'
      t.string :before_origin_path_digest, limit: 64, collation: 'utf8mb3_bin'
      t.string :after_origin_path_digest, limit: 64, collation: 'utf8mb3_bin'
      t.string :before_graph_digest, limit: 64, collation: 'utf8mb3_bin'
      t.string :after_graph_digest, limit: 64, collation: 'utf8mb3_bin'
      t.decimal :before_guid, precision: 20, scale: 0
      t.decimal :after_guid, precision: 20, scale: 0
      t.decimal :before_owner_fs_guid, precision: 20, scale: 0
      t.decimal :after_owner_fs_guid, precision: 20, scale: 0
      t.timestamps
    end
    add_index :storage_mutation_target_observations,
              %i[storage_mutation_attempt_id storage_mutation_target_id],
              unique: true, name: 'idx_storage_target_obs_attempt_target'
    add_index :storage_mutation_target_observations,
              :storage_mutation_target_id, name: 'idx_storage_target_obs_target'
    add_foreign_key :storage_mutation_target_observations, :storage_mutation_attempts,
                    on_delete: :restrict
    add_foreign_key :storage_mutation_target_observations, :storage_mutation_targets,
                    on_delete: :restrict

    add_index :transaction_confirmations, %i[done transaction_id],
              name: 'idx_transaction_confirmations_done_transaction'
  end

  private

  def add_snapshot_identity(table)
    add_column table, :zfs_guid, :decimal, precision: 20, scale: 0
    add_column table, :zfs_owner_fs_guid, :decimal, precision: 20, scale: 0
    add_column table, :zfs_path, :string, limit: 1024, collation: 'utf8mb3_bin'
    add_column table, :physical_presence, :integer, null: false, default: 0
    add_check_constraint table,
                         'physical_presence IN (0, 1, 2) AND ' \
                         '(physical_presence <> 1 OR ' \
                         '(zfs_path IS NOT NULL AND zfs_guid IS NOT NULL AND ' \
                         'zfs_owner_fs_guid IS NOT NULL))',
                         name: "chk_#{table}_present_identity"
  end

  def add_observation_reference(table)
    add_column table, :storage_observation_run_id, :bigint
    add_index table, :storage_observation_run_id,
              name: "idx_#{table}_storage_run"
    add_foreign_key table, :storage_observation_runs, on_delete: :restrict
  end
end
