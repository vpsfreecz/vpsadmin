class AddVpsState < ActiveRecord::Migration[7.2]
  def change
    add_column :vps_current_statuses, :state, :string, limit: 20, null: false, default: 'no_state'
    add_index :vps_current_statuses, :state

    add_column :vps_statuses, :state, :string, limit: 20, null: false, default: 'no_state'
    add_index :vps_statuses, :state

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute("UPDATE vps_current_statuses
                                               SET state = CASE
                                                           WHEN is_running = 1 THEN 'running'
                                                           ELSE 'stopped'
                                                           END")
        ActiveRecord::Base.connection.execute("UPDATE vps_statuses
                                               SET state = CASE
                                                           WHEN is_running = 1 THEN 'running'
                                                           ELSE 'stopped'
                                                           END")
      end
    end
  end
end
