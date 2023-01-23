class AddMonitoredEventActionState < ActiveRecord::Migration[6.1]
  def change
    add_column :monitored_events, :action_state, :text, null: true
  end
end
