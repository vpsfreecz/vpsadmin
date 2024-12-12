class AddOomReportRules < ActiveRecord::Migration[7.2]
  def change
    create_table :oom_report_rules do |t|
      t.references  :vps,                      null: false
      t.integer     :action,                   null: false
      t.string      :cgroup_pattern,           null: false, limit: 255
      t.bigint      :hit_count,                null: false, default: 0
      t.timestamps                             null: false
    end

    add_column :oom_reports, :ignored, :boolean, null: false, default: false
    add_column :oom_reports, :oom_report_rule_id, :bigint, null: true
    add_column :vpses, :implicit_oom_report_rule_hit_count, :bigint, null: false, default: 0
  end
end
