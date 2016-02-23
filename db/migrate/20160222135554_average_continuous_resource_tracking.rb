class AverageContinuousResourceTracking < ActiveRecord::Migration
  def change
    create_table :vps_current_statuses do |t|
      t.references   :vps,               null: false
      t.boolean      :status,            null: false
      t.boolean      :is_running,        null: false
      t.integer      :uptime,            null: true
      t.integer      :cpus,              null: true
      t.integer      :total_memory,      null: true
      t.integer      :total_swap,        null: true
      t.integer      :update_count,      null: false
      
      t.integer      :process_count,     null: true
      t.float        :cpu_user,          null: true
      t.float        :cpu_nice,          null: true
      t.float        :cpu_system,        null: true
      t.float        :cpu_idle,          null: true
      t.float        :cpu_iowait,        null: true
      t.float        :cpu_irq,           null: true
      t.float        :cpu_softirq,       null: true
      t.float        :loadavg,           null: true
      t.integer      :used_memory,       null: true
      t.integer      :used_swap,         null: true

      t.integer      :sum_process_count, null: true
      t.float        :sum_cpu_user,      null: true
      t.float        :sum_cpu_nice,      null: true
      t.float        :sum_cpu_system,    null: true
      t.float        :sum_cpu_idle,      null: true
      t.float        :sum_cpu_iowait,    null: true
      t.float        :sum_cpu_irq,       null: true
      t.float        :sum_cpu_softirq,   null: true
      t.float        :sum_loadavg,       null: true
      t.integer      :sum_used_memory,   null: true
      t.integer      :sum_used_swap,     null: true

      t.timestamps
    end

    add_index :vps_current_statuses, :vps_id, unique: true

    create_table :node_current_statuses do |t|
      t.references   :node,              null: false
      t.integer      :uptime,            null: true
      t.integer      :cpus,              null: true
      t.integer      :total_memory,      null: true
      t.integer      :total_swap,        null: true
      t.string       :vpsadmind_version, null: false, limit: 25
      t.string       :kernel,            null: false, limit: 25
      t.integer      :update_count,      null: false
      
      t.integer      :process_count,     null: true
      t.float        :cpu_user,          null: true
      t.float        :cpu_nice,          null: true
      t.float        :cpu_system,        null: true
      t.float        :cpu_idle,          null: true
      t.float        :cpu_iowait,        null: true
      t.float        :cpu_irq,           null: true
      t.float        :cpu_softirq,       null: true
      t.float        :cpu_guest,         null: true
      t.float        :loadavg,           null: true
      t.integer      :used_memory,       null: true
      t.integer      :used_swap,         null: true
      t.integer      :arc_c_max,         null: true
      t.integer      :arc_c,             null: true
      t.integer      :arc_size,          null: true
      t.float        :arc_hitpercent,    null: true

      t.integer      :sum_process_count, null: true
      t.float        :sum_cpu_user,      null: true
      t.float        :sum_cpu_nice,      null: true
      t.float        :sum_cpu_system,    null: true
      t.float        :sum_cpu_idle,      null: true
      t.float        :sum_cpu_iowait,    null: true
      t.float        :sum_cpu_irq,       null: true
      t.float        :sum_cpu_softirq,   null: true
      t.float        :sum_cpu_guest,     null: true
      t.float        :sum_loadavg,       null: true
      t.integer      :sum_used_memory,   null: true
      t.integer      :sum_used_swap,     null: true
      t.integer      :sum_arc_c_max,     null: true
      t.integer      :sum_arc_c,         null: true
      t.integer      :sum_arc_size,      null: true
      t.float        :sum_arc_hitpercent,null: true

      t.timestamps
    end

    add_index :node_current_statuses, :node_id, unique: true
    add_index :dataset_property_histories, :dataset_property_id

    remove_column :vps, :vps_status_id, :integer, null: true
    remove_column :servers, :node_status_id, :integer, null: true
    remove_column :vps_statuses, :updated_at, :datetime

    reversible do |dir|
      dir.up do
        # Filter VPS statuses - keep hourly history
        ActiveRecord::Base.connection.execute(
            "CREATE TABLE vps_statuses_new LIKE vps_statuses"
        )

        ActiveRecord::Base.connection.execute(
            "INSERT INTO vps_statuses_new (
              vps_id, status, is_running, cpus, total_memory, total_swap,
              uptime, process_count, cpu_user, cpu_nice, cpu_system, cpu_idle,
              cpu_iowait, cpu_irq, cpu_softirq, loadavg, used_memory, used_swap,
              created_at
            )

            SELECT
              vps_id, status, is_running, cpus, total_memory, total_swap, uptime,
              AVG(process_count), AVG(cpu_user), AVG(cpu_nice), AVG(cpu_system),
              AVG(cpu_idle), AVG(cpu_iowait), AVG(cpu_irq), AVG(cpu_softirq),
              AVG(loadavg), AVG(used_memory), AVG(used_swap), created_at
            FROM vps_statuses
            GROUP BY vps_id, DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')
            "
        )

        drop_table :vps_statuses
        rename_table :vps_statuses_new, :vps_statuses

        # Filter node statuses - keep hourly history
        # The status is logged every 15 minutes by default, but that is harder
        # to achieve here.
        ActiveRecord::Base.connection.execute(
            "CREATE TABLE node_statuses_new LIKE node_statuses"
        )

        ActiveRecord::Base.connection.execute(
            "INSERT INTO node_statuses_new (
              node_id, cpus, total_memory, total_swap, uptime, vpsadmind_version,
              kernel, process_count, cpu_user, cpu_nice, cpu_system, cpu_idle,
              cpu_iowait, cpu_irq, cpu_softirq, cpu_guest, loadavg, used_memory,
              used_swap, arc_c_max, arc_c, arc_size, arc_hitpercent, created_at
            )

            SELECT
              node_id, cpus, total_memory, total_swap, uptime, vpsadmind_version,
              kernel, AVG(process_count), AVG(cpu_user), AVG(cpu_nice),
              AVG(cpu_system), AVG(cpu_idle), AVG(cpu_iowait), AVG(cpu_irq),
              AVG(cpu_softirq), AVG(cpu_guest), AVG(loadavg), AVG(used_memory),
              AVG(used_swap), AVG(arc_c_max), AVG(arc_c), AVG(arc_size),
              AVG(arc_hitpercent), created_at
            FROM node_statuses
            GROUP BY node_id, DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')
            "
        )
        
        drop_table :node_statuses
        rename_table :node_statuses_new, :node_statuses

        # Filter dataset property history, keep hourly history
        ActiveRecord::Base.connection.execute(
            "CREATE TABLE dataset_property_histories_new LIKE dataset_property_histories"
        )

        ActiveRecord::Base.connection.execute(
            "INSERT INTO dataset_property_histories_new (
              dataset_property_id, value, created_at
            )

            SELECT
              dataset_property_id, AVG(value), created_at
            FROM dataset_property_histories
            GROUP BY dataset_property_id, DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')
            "
        )

        drop_table :dataset_property_histories
        rename_table :dataset_property_histories_new, :dataset_property_histories
      end
    end
  end
end
