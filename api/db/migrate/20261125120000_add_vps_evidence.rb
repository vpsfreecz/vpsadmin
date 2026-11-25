class AddVpsEvidence < ActiveRecord::Migration[8.1]
  def change
    add_column :incident_reports, :evidence_snapshot, :json

    create_table :vps_evidence_events do |t|
      t.string :signal, limit: 64, null: false
      t.bigint :node_id, null: false
      t.string :producer_epoch, limit: 64, null: false
      t.bigint :sequence, null: false
      t.integer :part, null: false
      t.integer :parts, null: false
      t.string :digest, limit: 64, null: false
      t.datetime :observed_at, precision: 6, null: false
      t.datetime :received_at, precision: 6, null: false
      t.json :facts, null: false
      t.boolean :current_stream, null: false, default: false
      t.index %i[node_id signal producer_epoch sequence part], unique: true, name: :vps_evidence_event_identity
      t.index %i[node_id signal observed_at id], name: :vps_evidence_event_stream
      t.index %i[node_id signal current_stream], name: :vps_evidence_stream_cursor
      t.index :received_at
    end

    create_table :vps_evidence_states do |t|
      t.string :signal, limit: 64, null: false
      t.bigint :vps_id, null: false
      t.bigint :user_id, null: false
      t.datetime :accounting_since, precision: 6
      t.bigint :accepted_us, null: false, default: 0
      t.datetime :last_incident_at, precision: 6
      t.datetime :complete_since, precision: 6
      t.bigint :node_id
      t.datetime :observed_at, precision: 6
      t.json :target
      t.index %i[vps_id signal], unique: true
      t.index %i[node_id signal]
    end

    create_table :vps_evidence_intervals do |t|
      t.string :signal, limit: 64, null: false
      t.bigint :vps_id, null: false
      t.bigint :user_id, null: false
      t.datetime :accounting_since, precision: 6
      t.bigint :incident_report_id
      t.datetime :from_at, precision: 6, null: false
      t.datetime :to_at, precision: 6, null: false
      t.bigint :credit_us, null: false
      t.datetime :accepted_at, precision: 6
      t.string :measurement, limit: 64
      t.string :peak_unit, limit: 32
      t.bigint :peak_value
      t.boolean :peak_is_lower_bound
      t.json :evidence, null: false
      t.index %i[vps_id signal incident_report_id to_at], name: :vps_evidence_interval_window
      t.index %i[incident_report_id id], name: :vps_evidence_interval_report
      t.index %i[incident_report_id accepted_at], name: :vps_evidence_interval_accepted
    end
  end
end
