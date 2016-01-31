module VpsAdmind
  class NodeStatus
    def initialize
      @cpus = SystemProbes::Cpus.new.count
    end

    def update
      node_id = $CFG.get(:vpsadmin, :server_id)
      time = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      nproc = SystemProbes::ProcessCounter.new.count
      uptime = SystemProbes::Uptime.new.uptime.round
      loadavg = SystemProbes::LoadAvg.new.avg
      kernel = SystemProbes::Kernel.new.version

      if linux?
        cpu = SystemProbes::CpuUsage.new.measure.to_percent
        mem = SystemProbes::Memory.new
        arc = SystemProbes::Arc.new
      end

      my = Db.new
      my.transaction do |t|
        sql = "INSERT INTO node_statuses
               SET node_id = #{node_id},
                 uptime = #{uptime},
                 process_count = #{nproc},"

        if linux?
          sql += "cpus = #{@cpus},
                cpu_user = #{cpu[:user]},
                cpu_nice = #{cpu[:nice]},
                cpu_system = #{cpu[:system]},
                cpu_idle = #{cpu[:idle]},
                cpu_iowait = #{cpu[:iowait]},
                cpu_irq = #{cpu[:irq]},
                cpu_softirq = #{cpu[:softirq]},
                cpu_guest = #{cpu[:guest]},
                total_memory = #{mem.total / 1024},
                used_memory = #{mem.used / 1024},
                total_swap = #{mem.swap_total / 1024},
                used_swap = #{mem.swap_used / 1024},
                arc_c_max = #{arc.c_max / 1024 / 1024},
                arc_c = #{arc.c / 1024 / 1024},
                arc_size = #{arc.size / 1024 / 1024},
                arc_hitpercent = #{arc.hit_percent},"
        end

        sql += "loadavg = #{loadavg[1]},
                vpsadmind_version = '#{VpsAdmind::VERSION}',
                kernel = '#{kernel}',
                created_at = '#{time}'"

        # When t.prepared is used, it raises TypeError: unsupported type: 1
        t.query(sql)

        t.prepared(
            'UPDATE servers SET node_status_id = ? WHERE server_id = ?',
            t.insert_id, node_id
        )
      end

      my.close
    end

    protected
    def linux?
      /solaris/ !~ RUBY_PLATFORM
    end
  end
end
