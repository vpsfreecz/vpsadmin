class AddOomReportsCgroup < ActiveRecord::Migration[7.0]
  def change
    add_column :oom_reports, :cgroup, :string, limit: 255, null: false, default: '/'
  end
end
