class AddDnsPrimaryTransferStates < ActiveRecord::Migration[8.1]
  def up
    validate_audit_integrity!

    add_column :dns_zones, :primary_transfer_tracking_started_at, :datetime, null: true
    add_column :dns_zones, :primary_transfer_generation, :string, limit: 36, null: true

    execute <<~SQL.squish
      UPDATE dns_zones
      SET primary_transfer_tracking_started_at = CURRENT_TIMESTAMP,
          primary_transfer_generation = UUID()
      WHERE enabled = TRUE AND zone_source = 1
    SQL

    add_reference :dns_server_zone_transfer_logs,
                  :dns_zone_transfer,
                  null: true,
                  index: true,
                  foreign_key: { on_delete: :nullify }
    add_foreign_key :dns_server_zone_transfer_logs,
                    :dns_server_zones,
                    on_delete: :cascade

    add_column :dns_server_zone_transfer_logs, :attempt_kind, :integer, null: true
    execute 'UPDATE dns_server_zone_transfer_logs SET attempt_kind = 6'
    add_column :dns_server_zone_transfer_logs, :failure_class, :integer, null: true
    add_column :dns_server_zone_transfer_logs, :primary_serial, :integer,
               unsigned: true, null: true
    add_column :dns_server_zone_transfer_logs, :secondary_serial, :integer,
               unsigned: true, null: true

    create_table :dns_server_zone_primary_transfer_states do |t|
      t.references :dns_server_zone, null: false,
                                     foreign_key: { on_delete: :cascade },
                                     index: { name: 'idx_dns_primary_transfer_states_on_server_zone' }
      t.references :dns_zone_transfer, null: false,
                                       foreign_key: { on_delete: :cascade },
                                       index: { name: 'idx_dns_primary_transfer_states_on_zone_transfer' }
      t.references :last_transfer_log, null: true,
                                       foreign_key: {
                                         to_table: :dns_server_zone_transfer_logs,
                                         on_delete: :nullify
                                       },
                                       index: { name: 'idx_dns_primary_transfer_states_on_last_log' }
      t.string :configuration_generation, limit: 36, null: false
      t.string :last_event_key, limit: 64, null: false
      t.integer :status, null: false
      t.integer :failure_class, null: true
      t.integer :last_attempt_kind, null: false
      t.datetime :failed_since, null: true
      t.datetime :last_attempt_at, null: false
      t.datetime :last_failure_at, null: true
      t.datetime :last_success_at, null: true
      t.datetime :alert_eligible_at, null: true
      t.datetime :reason_observed_at, null: true
      t.string :reason_code, limit: 40, null: true
      t.string :reason, limit: 255, null: true
      t.integer :primary_serial, unsigned: true, null: true
      t.integer :secondary_serial, unsigned: true, null: true
      t.timestamps null: false
    end

    add_index :dns_server_zone_primary_transfer_states,
              %i[dns_server_zone_id dns_zone_transfer_id],
              unique: true,
              name: 'idx_dns_primary_transfer_states_on_path'
    add_index :dns_server_zone_primary_transfer_states,
              %i[status alert_eligible_at],
              name: 'idx_dns_primary_transfer_states_on_alert'

    # Transaction confirmations remove parents with raw SQL, bypassing model
    # dependency callbacks. The foreign keys above keep asynchronously created
    # logs and path states consistent on create rollback and final deletion.
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'retain additive DNS readiness schema to preserve audit history'
  end

  private

  def validate_audit_integrity!
    orphan_ids = select_values(<<~SQL.squish)
      SELECT logs.id FROM dns_server_zone_transfer_logs logs
      LEFT JOIN dns_server_zones zones ON zones.id = logs.dns_server_zone_id
      WHERE zones.id IS NULL ORDER BY logs.id LIMIT 20
    SQL
    pointer_ids = select_values(<<~SQL.squish)
      SELECT zones.id FROM dns_server_zones zones
      LEFT JOIN dns_server_zone_transfer_logs logs ON logs.id = zones.last_transfer_log_id
      WHERE zones.last_transfer_log_id IS NOT NULL
        AND (logs.id IS NULL OR logs.dns_server_zone_id != zones.id)
      ORDER BY zones.id LIMIT 20
    SQL
    return if orphan_ids.empty? && pointer_ids.empty?

    raise ActiveRecord::MigrationError,
          'DNS audit integrity requires reconciliation before migration: ' \
          "orphan transfer log IDs=#{orphan_ids.join(',')}; " \
          "invalid latest-pointer server-zone IDs=#{pointer_ids.join(',')}"
  end
end
