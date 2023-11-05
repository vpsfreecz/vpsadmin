class AddMonitoredEventAlertCount < ActiveRecord::Migration[7.0]
  def change
    add_column :monitored_events, :alert_count, :integer, null: false, default: 0
  end
end
