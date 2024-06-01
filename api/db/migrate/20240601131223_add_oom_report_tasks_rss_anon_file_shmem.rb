class AddOomReportTasksRssAnonFileShmem < ActiveRecord::Migration[7.1]
  def change
    add_column :oom_report_tasks, :rss_anon, :integer, null: true
    add_column :oom_report_tasks, :rss_file, :integer, null: true
    add_column :oom_report_tasks, :rss_shmem, :integer, null: true
  end
end
