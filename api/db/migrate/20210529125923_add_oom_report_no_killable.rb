class AddOomReportNoKillable < ActiveRecord::Migration
  def change
    change_column_null :oom_reports, :killed_pid, true
    change_column_null :oom_reports, :killed_name, true
  end
end
