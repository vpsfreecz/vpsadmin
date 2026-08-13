class AddDnsPrimaryTransferStates < ActiveRecord::Migration[8.1]
  def up
    add_column :dns_zones, :primary_transfer_tracking_started_at, :datetime, null: true
    add_column :dns_zones, :primary_transfer_generation, :string, limit: 36, null: true

    execute <<~SQL.squish
      UPDATE dns_zones
      SET primary_transfer_tracking_started_at = CURRENT_TIMESTAMP,
          primary_transfer_generation = UUID()
      WHERE enabled = TRUE AND zone_source = 1
    SQL

    # Every pre-cutover row is intentionally discarded. The column remains
    # nullable at the database level because the coordinated rollback runs the
    # old supervisor against this irreversible schema; the new model requires
    # an attempt kind for all events it writes.
    execute <<~SQL.squish
      UPDATE dns_server_zones
      SET last_transfer_log_id = NULL,
          last_transfer_at = NULL,
          last_transfer_status = NULL,
          last_transfer_reason_code = NULL,
          last_transfer_reason = NULL,
          last_transfer_primary_addr = NULL,
          last_transfer_serial = NULL
    SQL
    execute 'DELETE FROM dns_server_zone_transfer_logs'

    add_reference :dns_server_zone_transfer_logs,
                  :dns_zone_transfer,
                  null: true,
                  index: true,
                  foreign_key: { on_delete: :nullify }
    add_foreign_key :dns_server_zone_transfer_logs,
                    :dns_server_zones,
                    on_delete: :cascade

    add_column :dns_server_zone_transfer_logs, :attempt_kind, :integer, null: true
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
          'deleted DNS transfer history cannot be reconstructed'
  end
end
