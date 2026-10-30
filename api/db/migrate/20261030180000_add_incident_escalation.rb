class AddIncidentEscalation < ActiveRecord::Migration[8.1]
  def change
    change_table :vpses do |t|
      t.boolean :incident_enforcement_enabled, null: false, default: true
      t.datetime :incident_accounting_since
      t.datetime :incident_last_stop_at
      t.bigint :incident_owner_transfer_chain_id
    end

    change_table :incident_reports do |t|
      t.string :source_key, limit: 64
      t.string :source_kind, limit: 32
      t.bigint :source_node_id
      t.string :source_action, limit: 16
      t.bigint :notification_chain_id
      t.datetime :notification_processed_at
      t.index :source_key, unique: true
      t.index %i[vps_id user_id codename detected_at], name: :incident_reports_accounting
    end

    create_table :vps_incident_policies do |t|
      t.bigint :vps_id, null: false
      t.string :incident_type, null: false, limit: 100
      t.integer :warning_limit_override
      t.integer :stop_limit_override
      t.datetime :last_warning_at
      t.timestamps
      t.index %i[vps_id incident_type], unique: true
    end

    create_table :vps_incident_actions do |t|
      t.bigint :vps_id, null: false
      t.bigint :user_id, null: false
      t.bigint :incident_report_id, null: false
      t.string :incident_type, null: false, limit: 100
      t.datetime :accounting_since
      t.string :kind, null: false, limit: 16
      t.string :state, null: false, default: 'pending', limit: 16
      t.bigint :transaction_chain_id
      t.datetime :completed_at
      t.boolean :repeated_stop, null: false, default: false
      t.integer :incident_count_7d, null: false
      t.integer :incident_count_30d, null: false
      t.string :mail_state, null: false, default: 'pending', limit: 16
      t.bigint :mail_chain_id
      t.bigint :mail_log_id
      t.datetime :retry_after
      t.text :error
      t.timestamps
      t.index %i[incident_report_id incident_type], unique: true
      t.index %i[vps_id state]
    end
  end
end
