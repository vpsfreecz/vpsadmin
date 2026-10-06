# frozen_string_literal: true

class AddStorageMaintenanceHandoffs < ActiveRecord::Migration[8.0]
  HANDOFF_COLUMNS = %w[handed_off_by_user_id handed_off_by_user_session_id
                       handed_off_by_user_login handoff_reason handed_off_at].freeze
  TERMINAL_CONSTRAINT = 'chk_storage_maintenance_terminal_audit'
  PREDECESSOR_AUDIT =
    "(state = 'reserved' AND revision = 1 AND abandoned_by_user_id IS NULL " \
    'AND abandoned_by_user_session_id IS NULL AND abandoned_by_user_login IS NULL ' \
    'AND abandonment_reason IS NULL AND abandoned_at IS NULL) OR ' \
    "(state = 'abandoned' AND revision = 2 AND abandoned_by_user_id IS NOT NULL " \
    'AND abandoned_by_user_id > 0 AND abandoned_by_user_session_id IS NOT NULL ' \
    'AND abandoned_by_user_session_id > 0 AND abandoned_by_user_login IS NOT NULL ' \
    'AND CHAR_LENGTH(TRIM(abandoned_by_user_login)) BETWEEN 1 AND 128 ' \
    'AND abandonment_reason IS NOT NULL ' \
    'AND CHAR_LENGTH(TRIM(abandonment_reason)) BETWEEN 1 AND 255 AND abandoned_at IS NOT NULL)'
  CONTRACT_ONE =
    "record_contract = 1 AND BINARY requested_profile = 'manual_storage_only_v1' " \
    "AND BINARY state IN ('reserved', 'abandoned') AND (#{PREDECESSOR_AUDIT})".freeze
  EMPTY_HANDOFF = HANDOFF_COLUMNS.map { |name| "#{name} IS NULL" }.join(' AND ').freeze
  SUCCESSOR_AUDIT =
    "(#{CONTRACT_ONE} AND #{EMPTY_HANDOFF}) OR " \
    "(record_contract = 2 AND BINARY requested_profile = 'manual_storage_only_v1' " \
    "AND BINARY state = 'handoff_pending' AND revision = 2 " \
    'AND abandoned_by_user_id IS NULL AND abandoned_by_user_session_id IS NULL ' \
    'AND abandoned_by_user_login IS NULL AND abandonment_reason IS NULL AND abandoned_at IS NULL ' \
    'AND handed_off_by_user_id IS NOT NULL AND handed_off_by_user_id > 0 ' \
    'AND handed_off_by_user_session_id IS NOT NULL AND handed_off_by_user_session_id > 0 ' \
    'AND handed_off_by_user_login IS NOT NULL ' \
    'AND CHAR_LENGTH(TRIM(handed_off_by_user_login)) BETWEEN 1 AND 128 ' \
    'AND handoff_reason IS NOT NULL AND CHAR_LENGTH(TRIM(handoff_reason)) BETWEEN 1 AND 255 ' \
    'AND handed_off_at IS NOT NULL)'.freeze

  def up
    # Validate the consumed predecessor before the first additive DDL statement.
    if unsupported_rows?(CONTRACT_ONE)
      raise ActiveRecord::IrreversibleMigration, 'unsupported storage maintenance predecessor'
    end

    add_column :storage_maintenance_runs, :handed_off_by_user_id, :integer, unsigned: true
    add_column :storage_maintenance_runs, :handed_off_by_user_session_id, :integer, unsigned: true
    add_column :storage_maintenance_runs, :handed_off_by_user_login, :string, limit: 128
    add_column :storage_maintenance_runs, :handoff_reason, :string
    add_column :storage_maintenance_runs, :handed_off_at, :datetime
    remove_check_constraint :storage_maintenance_runs, name: TERMINAL_CONSTRAINT
    add_check_constraint :storage_maintenance_runs, SUCCESSOR_AUDIT, name: TERMINAL_CONSTRAINT
  end

  def down
    # Never discard responsibility audit or reinterpret an unknown tuple.
    permitted = "#{CONTRACT_ONE} AND #{EMPTY_HANDOFF}"
    if unsupported_rows?(permitted)
      raise ActiveRecord::IrreversibleMigration, 'storage maintenance handoff audit must be retained'
    end

    remove_check_constraint :storage_maintenance_runs, name: TERMINAL_CONSTRAINT
    add_check_constraint :storage_maintenance_runs, PREDECESSOR_AUDIT, name: TERMINAL_CONSTRAINT
    HANDOFF_COLUMNS.reverse_each { |name| remove_column :storage_maintenance_runs, name }
  end

  private

  def unsupported_rows?(predicate)
    select_value(<<~SQL.squish).to_i > 0
      SELECT COUNT(*) FROM storage_maintenance_runs
      WHERE NOT COALESCE((#{predicate}), FALSE)
    SQL
  end
end
