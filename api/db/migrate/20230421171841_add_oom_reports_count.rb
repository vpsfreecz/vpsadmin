class AddOomReportsCount < ActiveRecord::Migration[7.0]
  def change
    add_column :oom_reports, :count, :integer, null: false, default: 1
  end
end
