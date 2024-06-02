class AddOomReportCounters < ActiveRecord::Migration[7.1]
  def change
    create_table :oom_report_counters do |t|
      t.references  :vps,                  null: false
      t.string      :cgroup,               null: false, limit: 255, default: '/'
      t.bigint      :counter,              null: false, default: 0
    end

    add_index :oom_report_counters, %i[vps_id cgroup], unique: true
  end
end
