module VpsAdmind
  class Transaction
    @@types = {
        :gen_known_hosts => 5,
        :backup_schedule => 5005,
        :backup_regular => 5006,
        :backup_snapshot => 5011,
        :rotate_snapshots => 5101,
        :dataset_create => 5201,
        :dataset_snapshot => 5204,
        :dataset_transfer => 5205,
        :send_mail => 9001,
    }

    @@labels = {
        3 => "Restart node",
        5 => "Known hosts",
        1001 => "Start",
        1002 => "Stop",
        1003 => "Restart",
        1101 => "Suspend",
        2001 => "Exec",
        2002 => "Passwd",
        2003 => "Limits",
        2004 => "Hostname",
        2005 => "Nameserver",
        2006 => "IP +",
        2007 => "IP -",
        2008 => "Applyconfig",
        3001 => "Create",
        3002 => "Delete",
        3003 => "Reinstall",
        3004 => "Clone",
        3005 => "Clone",
        4011 => "Prepare migration",
        4021 => "Migrate (1)",
        4022 => "Migrate (2)",
        4031 => "Cleanup",
        5001 => "Restore (step 1)",
        5002 => "Restore (step 2)",
        5003 => "Restore (step 3)",
        5004 => "Download backup",
        5005 => "On-demand backup",
        5006 => "Regular backup",
        5011 => "Snapshot",
        5021 => "Trash backups",
        5101 => "Rotate snapshots",
        5201 => "Dataset +",
        5202 => "Dataset *",
        5203 => "Dataset -",
        5204 => 'Snapshot',
        5205 => 'Transfer',
        5301 => "Mounts",
        5302 => "Mount",
        5303 => "Umount",
        5304 => "Remount",
        7201 => "IP reg",
        7301 => "Create config",
        7302 => "Delete config",
        8001 => "Features",
        9001 => "Mail",
    }

    def initialize(db = nil)
      @db = db || Db.new
    end

    def cluster_wide(p)
      rs = @db.query("SELECT server_id FROM servers ORDER BY server_id")
      rs.each_hash do |r|
        p[:node] = r["server_id"].to_i
        queue(p)
      end
    end

    def prepare(p)
      queue(p, false)
    end

    def queue(p, confirmed = true)
      param = encode_param(p[:param])

      @db.prepared('INSERT INTO transactions (`t_time`, `t_m_id`, `t_server`, `t_vps`, `t_type`,
                                              `t_depends_on`, `t_urgent`, `t_priority`, `t_param`,
                                              `t_done`, `t_success`)
                   VALUES (UNIX_TIMESTAMP(NOW()), ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)',
                   p[:m_id], p[:node], p[:vps], p[:type].class == Symbol ? @@types[p[:type]] : p[:type],
                   p[:depends], p[:urgent] || 0, p[:priority] || 0, param, confirmed ? 0 : 2)

      @db.insert_id
    end

    def confirm(id, param=nil)
      args = []
      args << encode_param(param) if param
      args << id

      @db.prepared("UPDATE transactions SET t_done = 0 #{param ? ', t_param = ?' : ''} WHERE t_id = ? AND t_done = 2", *args)
    end

    def confirm_create(*args)
      add_confirmable(0, *args)
    end

    def confirm_destroy(*args)
      add_confirmable(1, *args)
    end

    def Transaction.label(type)
      @@labels[type]
    end

    protected
    def add_confirmable(type, t_id, klass, table, id)
      @db.prepared(
          'INSERT INTO transaction_confirmations (transaction_id, class_name, table_name, row_id, confirm, done)
          VALUES (?, ?, ?, ?, ?, 0)',
          t_id, klass, table, id, type
      )
    end

    def encode_param(p)
      ret = p.to_json
      ret == 'null' ? '{}' : ret
    end
  end
end
