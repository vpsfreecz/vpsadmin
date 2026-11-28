class AddVpsEvidenceDailyTotals < ActiveRecord::Migration[8.1]
  def change
    create_table :vps_evidence_daily_totals do |t|
      t.date :day, null: false
      t.bigint :vps_id, null: false
      t.string :signal, limit: 64, null: false
      t.bigint :user_id, null: false
      t.datetime :accounting_since, precision: 6
      t.string :accounting_epoch_key, limit: 27, null: false
      t.bigint :recorded_us, null: false, default: 0
      t.datetime :first_accepted_at, precision: 6, null: false
      t.datetime :last_accepted_at, precision: 6, null: false
      t.index %i[vps_id signal user_id accounting_epoch_key day], unique: true, name: :vps_evidence_daily_identity
      t.index :day
    end
  end
end
