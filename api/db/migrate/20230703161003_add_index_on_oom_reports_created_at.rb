class AddIndexOnOomReportsCreatedAt < ActiveRecord::Migration[7.0]
  def change
    add_index :oom_reports, :created_at
  end
end
