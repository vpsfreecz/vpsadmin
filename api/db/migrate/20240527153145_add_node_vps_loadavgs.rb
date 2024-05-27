class AddNodeVpsLoadavgs < ActiveRecord::Migration[7.1]
  def change
    add_column :node_current_statuses, :loadavg1, :float, null: false, default: 0.0
    add_column :node_current_statuses, :loadavg5, :float, null: false, default: 0.0
    add_column :node_current_statuses, :loadavg15, :float, null: false, default: 0.0

    add_column :node_current_statuses, :sum_loadavg1, :float, null: false, default: 0.0
    add_column :node_current_statuses, :sum_loadavg5, :float, null: false, default: 0.0
    add_column :node_current_statuses, :sum_loadavg15, :float, null: false, default: 0.0

    add_column :node_statuses, :loadavg1, :float, null: false, default: 0.0
    add_column :node_statuses, :loadavg5, :float, null: false, default: 0.0
    add_column :node_statuses, :loadavg15, :float, null: false, default: 0.0

    change_column_null :node_current_statuses, :loadavg, true
    change_column_null :node_statuses, :loadavg, true

    reversible do |dir|
      dir.up do
        ActiveRecord::Base.connection.execute('
          UPDATE node_current_statuses
          SET loadavg5 = loadavg, sum_loadavg5 = sum_loadavg
          WHERE loadavg IS NOT NULL
        ')
        ActiveRecord::Base.connection.execute('
          UPDATE node_statuses SET loadavg5 = loadavg WHERE loadavg IS NOT NULL
        ')
      end

      dir.down do
        ActiveRecord::Base.connection.execute('
          UPDATE node_current_statuses SET loadavg = loadavg5, sum_loadavg = sum_loadavg5
        ')
        ActiveRecord::Base.connection.execute('
          UPDATE node_statuses SET loadavg = loadavg5
        ')
      end
    end

    # TODO: in the future, we should remove loadavg and sum_loadavg columns from
    # node_current_statuses and node_statuses. We're leaving it behind, because currently
    # nasbox is outdated and would get stuck without the columns.

    add_column :vps_current_statuses, :loadavg1, :float, null: true
    rename_column :vps_current_statuses, :loadavg, :loadavg5
    add_column :vps_current_statuses, :loadavg15, :float, null: true

    add_column :vps_current_statuses, :sum_loadavg1, :float, null: true
    rename_column :vps_current_statuses, :sum_loadavg, :sum_loadavg5
    add_column :vps_current_statuses, :sum_loadavg15, :float, null: true

    add_column :vps_statuses, :loadavg1, :float, null: true
    rename_column :vps_statuses, :loadavg, :loadavg5
    add_column :vps_statuses, :loadavg15, :float, null: true
  end
end
