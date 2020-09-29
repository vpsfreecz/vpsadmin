class AddVpsOomReports < ActiveRecord::Migration
  def change
    create_table :oom_reports do |t|
      t.references  :vps,                       null: false
      t.integer     :invoked_by_pid,            null: false
      t.string      :invoked_by_name,           null: false, limit: 50
      t.integer     :killed_pid,                null: false
      t.string      :killed_name,               null: false, limit: 50
      t.boolean     :processed,                 null: false, default: 0
      t.datetime    :created_at,                null: false
      t.datetime    :reported_at,               null: true
    end

    add_index :oom_reports, :vps_id
    add_index :oom_reports, :processed

    create_table :oom_report_usages do |t|
      t.references  :oom_report,                null: false
      t.string      :memtype,                   null: false, limit: 20
      t.decimal     :usage,                     null: false, precision: 40, scale: 0
      t.decimal     :limit,                     null: false, precision: 40, scale: 0
      t.decimal     :failcnt,                   null: false, precision: 40, scale: 0
    end

    add_index :oom_report_usages, :oom_report_id

    create_table :oom_report_stats do |t|
      t.references  :oom_report,                null: false
      t.string      :parameter,                 null: false, limit: 30
      t.decimal     :value,                     null: false, precision: 40, scale: 0
    end

    add_index :oom_report_stats, :oom_report_id

    create_table :oom_report_tasks do |t|
      t.references  :oom_report,                null: false
      t.string      :name,                      null: false, limit: 50
      t.integer     :host_pid,                  null: false
      t.integer     :vps_pid,                   null: true
      t.integer     :host_uid,                  null: false
      t.integer     :vps_uid,                   null: true
      t.integer     :tgid,                      null: false
      t.integer     :total_vm,                  null: false
      t.integer     :rss,                       null: false
      t.integer     :pgtables_bytes,            null: false
      t.integer     :swapents,                  null: false
      t.integer     :oom_score_adj,             null: false
    end

    add_index :oom_report_tasks, :oom_report_id
  end
end
