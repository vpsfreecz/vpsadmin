class AddPasswordEventCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :password_event_counters do |t|
      t.string :name, limit: 64, null: false
      t.bigint :event_count, unsigned: true, null: false, default: 0
      t.datetime :last_occurred_at
      t.timestamps
    end

    add_index :password_event_counters, :name, unique: true
  end
end
