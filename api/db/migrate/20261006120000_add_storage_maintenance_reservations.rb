# frozen_string_literal: true

class AddStorageMaintenanceReservations < ActiveRecord::Migration[7.1]
  def up
    create_table :storage_maintenance_runs do |t|
      t.string :request_id, limit: 36, null: false, collation: 'utf8mb3_bin'
      t.integer :record_contract, null: false
      t.string :requested_profile, limit: 64, null: false
      t.string :state, limit: 32, null: false
      t.integer :revision, null: false
      t.bigint :freeze_epoch, null: false, unsigned: true
      t.text :requested_scope_json, size: :medium, null: false
      t.string :requested_scope_digest, limit: 64, null: false, collation: 'utf8mb3_bin'
      t.integer :acquired_by_user_id, null: false, unsigned: true
      t.integer :acquired_by_user_session_id, null: false, unsigned: true
      t.string :acquired_by_user_login, limit: 128, null: false
      t.string :acquisition_reason, null: false
      t.datetime :acquired_at, null: false
      t.integer :abandoned_by_user_id, unsigned: true
      t.integer :abandoned_by_user_session_id, unsigned: true
      t.string :abandoned_by_user_login, limit: 128
      t.string :abandonment_reason
      t.datetime :abandoned_at
    end
    add_index :storage_maintenance_runs, :request_id, unique: true
    add_check_constraint :storage_maintenance_runs,
                         "request_id REGEXP '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'",
                         name: 'chk_storage_maintenance_uuid'
    add_check_constraint :storage_maintenance_runs,
                         'record_contract > 0 AND CHAR_LENGTH(TRIM(requested_profile)) BETWEEN 1 AND 64',
                         name: 'chk_storage_maintenance_contract'
    add_check_constraint :storage_maintenance_runs,
                         'JSON_VALID(requested_scope_json) AND OCTET_LENGTH(requested_scope_json) <= 1048576 ' \
                         "AND requested_scope_digest REGEXP '^[0-9a-f]{64}$'",
                         name: 'chk_storage_maintenance_scope'
    add_check_constraint :storage_maintenance_runs,
                         'acquired_by_user_id > 0 AND acquired_by_user_session_id > 0 ' \
                         'AND CHAR_LENGTH(TRIM(acquired_by_user_login)) BETWEEN 1 AND 128 ' \
                         'AND CHAR_LENGTH(TRIM(acquisition_reason)) BETWEEN 1 AND 255',
                         name: 'chk_storage_maintenance_acquisition'
    add_check_constraint :storage_maintenance_runs,
                         "(state = 'reserved' AND revision = 1 AND abandoned_by_user_id IS NULL " \
                         'AND abandoned_by_user_session_id IS NULL AND abandoned_by_user_login IS NULL ' \
                         'AND abandonment_reason IS NULL AND abandoned_at IS NULL) OR ' \
                         "(state = 'abandoned' AND revision = 2 AND abandoned_by_user_id IS NOT NULL " \
                         'AND abandoned_by_user_id > 0 AND abandoned_by_user_session_id IS NOT NULL ' \
                         'AND abandoned_by_user_session_id > 0 AND abandoned_by_user_login IS NOT NULL ' \
                         'AND CHAR_LENGTH(TRIM(abandoned_by_user_login)) BETWEEN 1 AND 128 ' \
                         'AND abandonment_reason IS NOT NULL ' \
                         'AND CHAR_LENGTH(TRIM(abandonment_reason)) BETWEEN 1 AND 255 AND abandoned_at IS NOT NULL)',
                         name: 'chk_storage_maintenance_terminal_audit'
    add_column :storage_freeze_controls, :active_maintenance_run_id, :bigint
    add_index :storage_freeze_controls, :active_maintenance_run_id, unique: true
    add_foreign_key :storage_freeze_controls, :storage_maintenance_runs,
                    column: :active_maintenance_run_id, on_delete: :restrict
  end

  def down
    # Audit rows have already been consumed once any reservation exists.
    if select_value('SELECT COUNT(*) FROM storage_maintenance_runs').to_i > 0 ||
       select_value('SELECT COUNT(*) FROM storage_freeze_controls WHERE active_maintenance_run_id IS NOT NULL').to_i > 0
      raise ActiveRecord::IrreversibleMigration, 'storage maintenance audit must be retained'
    end

    remove_foreign_key :storage_freeze_controls, column: :active_maintenance_run_id
    remove_index :storage_freeze_controls, :active_maintenance_run_id
    remove_column :storage_freeze_controls, :active_maintenance_run_id
    drop_table :storage_maintenance_runs
  end
end
