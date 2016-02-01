class ContinuosResourceTracking < ActiveRecord::Migration
  def up
    create_table :vps_statuses do |t|
      t.references   :vps,               null: false
      t.boolean      :status,            null: false
      t.boolean      :is_running,        null: false
      t.integer      :uptime,            null: true
      t.integer      :process_count,     null: true
      t.integer      :cpus,              null: false
      t.float        :cpu_user,          null: true
      t.float        :cpu_nice,          null: true
      t.float        :cpu_system,        null: true
      t.float        :cpu_idle,          null: true
      t.float        :cpu_iowait,        null: true
      t.float        :cpu_irq,           null: true
      t.float        :cpu_softirq,       null: true
      t.float        :cpu_guest,         null: true
      t.float        :loadavg,           null: true
      t.integer      :total_memory,      null: true
      t.integer      :used_memory,       null: true
      t.integer      :total_swap,        null: true
      t.integer      :used_swap,         null: true
      t.datetime     :created_at,        null: true
    end

    add_column :vps, :vps_status_id, :integer, null: true

    create_table :node_statuses do |t|
      t.references   :node,              null: false
      t.integer      :uptime,            null: false
      t.integer      :process_count,     null: true
      t.integer      :cpus,              null: true
      t.float        :cpu_user,          null: true
      t.float        :cpu_nice,          null: true
      t.float        :cpu_system,        null: true
      t.float        :cpu_idle,          null: true
      t.float        :cpu_iowait,        null: true
      t.float        :cpu_irq,           null: true
      t.float        :cpu_softirq,       null: true
      t.float        :cpu_guest,         null: true
      t.integer      :total_memory,      null: true
      t.integer      :used_memory,       null: true
      t.integer      :total_swap,        null: true
      t.integer      :used_swap,         null: true
      t.integer      :arc_c_max,         null: true
      t.integer      :arc_c,             null: true
      t.integer      :arc_size,          null: true
      t.float        :arc_hitpercent,    null: true
      t.float        :loadavg,           null: false
      t.string       :vpsadmind_version, null: false, limit: 25
      t.string       :kernel,            null: false, limit: 25
      t.datetime     :created_at,        null: true
    end

    add_column :servers, :node_status_id, :integer, null: true
    add_column :servers, :cpus, :integer, null: false
    add_column :servers, :total_memory, :integer, null: false
    add_column :servers, :total_swap, :integer, null: false
    
    drop_table :vps_status
    drop_table :servers_status
  end

  # The rollback does not return unsigned columns, as ActiveRecord does
  # not support it.
  def down
    create_table :vps_status do |t|
      t.integer      :vps_id,            null: false
      t.boolean      :vps_up,            null: true
      t.integer      :vps_nproc,         null: true
      t.integer      :vps_vm_used_mb,    null: true
      t.integer      :vps_disk_used_mb,  null: true
      t.string       :vps_admin_ver,     null: true,  default: 'not set'
      t.datetime     :created_at,        null: true
    end

    add_index :vps_status, :vps_id, unique: true

    create_table :servers_status do |t|
      t.integer      :server_id,         null: false
      t.integer      :ram_free_mb,       null: true
      t.float        :disk_vz_free_gb,   null: true
      t.float        :cpu_load,          null: true
      t.boolean      :daemon,            null: false
      t.string       :vpsadmin_version,  null: true,  limit: 63
      t.string       :kernel,            null: false, limit: 50
      t.datetime     :created_at,        null: true
    end

    remove_column :vps, :vps_status_id
    remove_column :servers, :node_status_id
    remove_column :servers, :cpus
    remove_column :servers, :total_memory
    remove_column :servers, :total_swap

    drop_table :vps_statuses
    drop_table :node_statuses
  end
end
