class Setup < ActiveRecord::Migration
  def change
    create_table :policy_violations do |t|
      t.string      :policy_name,         null: false, limit: 100
      t.string      :class_name,          null: false, limit: 255
      t.integer     :row_id,              null: false
      t.integer     :state,               null: false
      t.timestamps,                       null: false
      t.datetime    :closed_at,           null: true
    end

    add_index :policy_violations, :policy_name
    add_index :policy_violations, :class_name
    add_index :policy_violations, :row_id
    add_index :policy_violations, :state

    create_table :policy_violation_logs do |t|
      t.references  :policy_violation,    null: false
      t.boolean     :passed,              null: false
      t.string      :value,               null: false, limit: 255
      t.datetime    :created_at,          null: false
    end

    add_index :policy_violation_logs, :policy_violation_id
    add_index :policy_violation_logs, :passed
  end
end
