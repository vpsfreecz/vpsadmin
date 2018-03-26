require 'ostruct'

module NodeCtld
  class NodeStatus
    def initialize
      @cpus = SystemProbes::Cpus.new.count
    end

    def init(db)
      mem = SystemProbes::Memory.new

      db.prepared(
        'UPDATE nodes
        SET cpus = ?, total_memory = ?, total_swap = ?
        WHERE id = ?',
        @cpus, mem.total / 1024, mem.swap_total / 1024,
        $CFG.get(:vpsadmin, :node_id)
      )
    end

    def update(db = nil)
      t = Time.now.utc

      info = OpenStruct.new({
        node_id: $CFG.get(:vpsadmin, :node_id),
        time: t,
        str_time: t.strftime('%Y-%m-%d %H:%M:%S'),
        nproc: SystemProbes::ProcessCounter.new.count,
        uptime: SystemProbes::Uptime.new.uptime.round,
        loadavg: SystemProbes::LoadAvg.new.avg,
      })

      info.kernel = SystemProbes::Kernel.new.version
      info.cpu = SystemProbes::CpuUsage.new.measure.to_percent
      info.mem = SystemProbes::Memory.new

      info.arc = SystemProbes::Arc.new if hypervisor? || storage?

      my = db || Db.new

      if @last_log.nil? || (@last_log + $CFG.get(:vpsadmin, :status_log_interval)) < t
        log_status(my, info)
        reset_status(my, info)
        @last_log = t

      else
        update_status(my, info)
      end

      my.close unless db

    rescue SystemCommandFailed => e
      log(:fatal, :node_status, e.message)
    end

    protected
    def hypervisor?
      $CFG.get(:vpsadmin, :type) == :node
    end

    def storage?
      $CFG.get(:vpsadmin, :type) == :storage
    end

    def log_status(db, info)
      db.query(
        "INSERT INTO node_statuses (
          node_id, uptime, cpus, total_memory, total_swap, process_count,
          cpu_user, cpu_nice, cpu_system, cpu_idle, cpu_iowait, cpu_irq, cpu_softirq,
          loadavg, used_memory, used_swap, arc_c_max, arc_c, arc_size, arc_hitpercent,
          vpsadmind_version, kernel, created_at
        )

        SELECT
          node_id, uptime, cpus, total_memory, total_swap,
          sum_process_count / update_count,
          sum_cpu_user / update_count,
          sum_cpu_nice / update_count,
          sum_cpu_system / update_count,
          sum_cpu_idle / update_count,
          sum_cpu_iowait / update_count,
          sum_cpu_irq / update_count,
          sum_cpu_softirq / update_count,
          sum_loadavg / update_count,
          sum_used_memory / update_count,
          sum_used_swap / update_count,
          sum_arc_c_max / update_count,
          sum_arc_c / update_count,
          sum_arc_size / update_count,
          sum_arc_hitpercent / update_count,
          vpsadmind_version,
          kernel,
          '#{info.str_time}'

        FROM node_current_statuses WHERE node_id = #{info.node_id}
        "
      )
    end

    def reset_status(db, info)
      sql = "
          uptime = #{info.uptime},
          process_count = #{info.nproc},
          vpsadmind_version = '#{NodeCtld::VERSION}',
          kernel = '#{info.kernel}',
          cpus = #{@cpus},
          cpu_user = #{info.cpu[:user]},
          cpu_nice = #{info.cpu[:nice]},
          cpu_system = #{info.cpu[:system]},
          cpu_idle = #{info.cpu[:idle]},
          cpu_iowait = #{info.cpu[:iowait]},
          cpu_irq = #{info.cpu[:irq]},
          cpu_softirq = #{info.cpu[:softirq]},
          total_memory = #{info.mem.total / 1024},
          used_memory = #{info.mem.used / 1024},
          total_swap = #{info.mem.swap_total / 1024},
          used_swap = #{info.mem.swap_used / 1024},
          sum_loadavg = loadavg,
          sum_process_count = process_count,
          sum_used_memory = used_memory,
          sum_used_swap = used_swap,
          sum_cpu_user = cpu_user,
          sum_cpu_nice = cpu_nice,
          sum_cpu_system = cpu_system,
          sum_cpu_idle = cpu_idle,
          sum_cpu_iowait = cpu_iowait,
          sum_cpu_irq = cpu_irq,
          sum_cpu_softirq = cpu_softirq,"

      if hypervisor? && info.cpu[:guest]
        sql += "cpu_guest = #{info.cpu[:guest]},
            sum_cpu_guest = cpu_guest,"
      end

      if hypervisor? || storage?
        sql += "arc_c_max = #{info.arc.c_max / 1024 / 1024},
            arc_c = #{info.arc.c / 1024 / 1024},
            arc_size = #{info.arc.size / 1024 / 1024},
            arc_hitpercent = #{info.arc.hit_percent},"
      else
        sql += "arc_c_max = NULL,
            arc_c = NULL,
            arc_size = NULL,
            arc_hitpercent = NULL,"
      end

      sql += "sum_arc_c_max = arc_c_max,
            sum_arc_c = arc_c,
            sum_arc_size = arc_size,
            sum_arc_hitpercent = arc_hitpercent,"

      sql += "loadavg = #{info.loadavg[5]},"

      db.query(
          "INSERT INTO node_current_statuses SET
            node_id = #{info.node_id},
            #{sql}
            update_count = 1,
            created_at = '#{info.str_time}'

          ON DUPLICATE KEY UPDATE
            #{sql}
            update_count = 1,
            created_at = '#{info.str_time}',
            updated_at = NULL
          "
      )
    end

    def update_status(db, info)
      sql = "
          uptime = #{info.uptime},
          process_count = #{info.nproc},
          sum_process_count = sum_process_count + process_count,
          cpu_user = #{info.cpu[:user]},
          cpu_nice = #{info.cpu[:nice]},
          cpu_system = #{info.cpu[:system]},
          cpu_idle = #{info.cpu[:idle]},
          cpu_iowait = #{info.cpu[:iowait]},
          cpu_irq = #{info.cpu[:irq]},
          cpu_softirq = #{info.cpu[:softirq]},
          total_memory = #{info.mem.total / 1024},
          used_memory = #{info.mem.used / 1024},
          total_swap = #{info.mem.swap_total / 1024},
          used_swap = #{info.mem.swap_used / 1024},

          sum_loadavg = sum_loadavg + loadavg,
          sum_used_memory = sum_used_memory + used_memory,
          sum_used_swap = sum_used_swap + used_swap,
          sum_cpu_user = sum_cpu_user + cpu_user,
          sum_cpu_nice = sum_cpu_nice + cpu_nice,
          sum_cpu_system = sum_cpu_system + cpu_system,
          sum_cpu_idle = sum_cpu_idle + cpu_idle,
          sum_cpu_iowait = sum_cpu_iowait + cpu_iowait,
          sum_cpu_irq = sum_cpu_irq + cpu_irq,
          sum_cpu_softirq = sum_cpu_softirq + cpu_softirq,"

      if hypervisor? && info.cpu[:guest]
        sql += "cpu_guest = #{info.cpu[:guest]},
            sum_cpu_guest = sum_cpu_guest + cpu_guest,"
      end

      if hypervisor? || storage?
        sql += "arc_c_max = #{info.arc.c_max / 1024 / 1024},
            arc_c = #{info.arc.c / 1024 / 1024},
            arc_size = #{info.arc.size / 1024 / 1024},
            arc_hitpercent = #{info.arc.hit_percent},

            sum_arc_c_max = sum_arc_c_max + arc_c_max,
            sum_arc_c = sum_arc_c + arc_c,
            sum_arc_size = sum_arc_size + arc_size,
            sum_arc_hitpercent = sum_arc_hitpercent + arc_hitpercent,"
      end

      sql += "loadavg = #{info.loadavg[5]},"

      db.query(
          "INSERT INTO node_current_statuses SET
            node_id = #{info.node_id},
            #{sql}
            update_count = 1,
            created_at = '#{info.str_time}'

          ON DUPLICATE KEY UPDATE
            #{sql}
            update_count = update_count + 1,
            updated_at = '#{info.str_time}'
          "
      )
    end
  end
end
