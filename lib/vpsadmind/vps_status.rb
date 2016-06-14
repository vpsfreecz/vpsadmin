module VpsAdmind
  class VpsStatus
    include Utils::Log
    include Utils::System
    include Utils::Vz
    include Utils::Vps

    @@mutex = Mutex.new

    def initialize(vps_ids = nil)
      @vps_ids = vps_ids
    end

    # If `db_in` is not provided, new connection to DB is opened and closed
    # when the status is updated.
    # @param db_in [VpsAdmind::Db]
    def update(db_in = nil)
      @@mutex.synchronize do
        db = db_in || Db.new
        safe_update(db)
        db.close unless db_in
      end
    end

    def safe_update(db)
      db_vpses = {}

      fetch_vpses(db).each_hash do |row|
        db_vpses[ row['vps_id'].to_i ] = {
            :read_hostname => row['manage_hostname'].to_i == 0,
            :last_status_id => row['status_id'] && row['status_id'].to_i,
            :last_is_running => row['is_running'].to_i == 1,
            :status_time => row['created_at'] && Time.strptime(
                row['created_at'] + ' UTC',
                '%Y-%m-%d %H:%M:%S %Z'
            ),
            :last_cpus => row['cpus'] && row['cpus'].to_i,
            :last_total_memory => row['total_memory'] && row['total_memory'].to_i,
            :last_total_swap => row['total_swap'] && row['total_swap'].to_i,
        }
      end

      vzlist.each do |vps|
        _, db_vps = db_vpses.detect { |k, v| k == vps[:veid] }
        next unless db_vps

        db_vps.update({
            :exists => true,
            :running => vps[:status] == 'running',
            :uptime => vps[:uptime],
            :nproc => vps[:numproc][:held],
            :cpus => vps[:cpus],
            :total_memory => vps[:physpages][:limit] / 1024 * 4,
            :used_memory => vps[:physpages][:held] / 1024 * 4,
            :total_swap => vps[:swappages][:limit] / 1024 * 4,
            :used_swap => vps[:swappages][:held] / 1024 * 4,
            :cpu => SystemProbes::CpuUsage.new,
        })

        if vps[:physpages][:limit] == 9223372036854775807  # unlimited
          db_vps[:total_memory] = 0
        end

        # If a VPS is stopped while the vzlist is run, it may say that status is
        # 'running', but later that it has zero processes or no load avg.
        if db_vps[:nproc] == 0 || vps[:laverage].nil? || db_vps[:uptime] == 0
          db_vps[:running] = false
        end

        if db_vps[:running]
          db_vps[:loadavg] = vps[:laverage][1]

          if db_vps[:read_hostname]
            run_or_skip(db_vps) do
              db_vps[:hostname] = vzctl(:exec, vps[:veid], 'hostname')[:output].strip
            end

            if !db_vps[:hostname] || db_vps[:hostname].empty?
              db_vps[:hostname] = 'unable to read'
            end
          end
        end
      end

      db_vpses.each do |vps_id, vps|
        next if !vps[:exists] || !vps[:running] || vps[:skip]
        
        run_or_skip(vps) do
          # Initial run to make sure that all libraries are loaded in memory and
          # consequent calls will be as fast as possible.
          vzctl(:exec, vps_id, 'cat /proc/stat > /dev/null')

          # First measurement
          vps[:cpu].measure_once(vzctl(:exec, vps_id, 'cat /proc/stat')[:output])

          sleep(0.2)
        
          # Final measurement
          vps[:cpu].measure_once(vzctl(:exec, vps_id, 'cat /proc/stat')[:output])
        end
      end

      # Save results to db
      db_vpses.each do |vps_id, vps|
        next unless vps[:exists]
       
        t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

        # The VPS is not running
        if !vps[:running] && vps[:last_status_id] && !vps[:last_is_running]
          db.prepared(
              'UPDATE vps_current_statuses SET updated_at = ? WHERE vps_id = ?',
              t, vps_id
          )
          next
        end

        if state_changed?(vps) || status_expired?(vps)
          log_status(db, t, vps_id)
          reset_status(db, t, vps_id, vps)

        else
          update_status(db, t, vps_id, vps)
        end

        if vps[:hostname]
          db.prepared(
              'UPDATE vps SET vps_hostname = ? WHERE vps_id = ?',
              vps[:hostname], vps_id
          )
        end
      end

    rescue CommandFailed => e
      log(:fatal, :vps_status, e.message)
    end

    protected
    def fetch_vpses(db)
      sql = "
          SELECT vps.vps_id, vps.manage_hostname, st.id AS status_id, st.is_running,
                 st.cpus, st.total_memory, st.total_swap, st.created_at
          FROM vps
          LEFT JOIN vps_current_statuses st ON st.vps_id = vps.vps_id
          WHERE
            vps_server = #{$CFG.get(:vpsadmin, :server_id)}
            AND object_state < 3"

      if @vps_ids
        sql += " AND vps.vps_id IN (#{@vps_ids.join(',')})"
      end
      
      db.query(sql)
    end

    def vzlist
      fields = %w(veid status cpus physpages swappages numproc uptime laverage)
      
      cmd = "#{$CFG.get(:vz, :vzlist)} -ajH -o#{fields.join(',')}"

      if @vps_ids
        cmd += " #{@vps_ids.join(' ')}"
      end

      JSON.parse(
        syscmd2(cmd, {:stderr => false})[:output],
        :symbolize_names => true
      )

    rescue JSON::ParserError => e
      raise CommandFailed.new(cmd, 0, e.message)
    end

    def run_or_skip(vps)
      yield

    rescue CommandFailed => e
      log(:warn, :vps, e.message)
      vps[:skip] = true
    end

    def state_changed?(vps)
      vps[:running] != vps[:last_is_running] \
        || vps[:cpus] != vps[:last_cpus] \
        || vps[:total_memory] != vps[:last_total_memory] \
        || vps[:total_swap] != vps[:last_total_swap]
    end

    def status_expired?(vps)
      (vps[:status_time] + $CFG.get(:vpsadmin, :vps_status_log_interval)) < Time.now.utc
    end

    def log_status(db, t, vps_id)
      db.query(
          "INSERT INTO vps_statuses (
            vps_id, status, is_running, uptime, cpus, total_memory, total_swap,
            process_count, cpu_user, cpu_nice, cpu_system, cpu_idle, cpu_iowait,
            cpu_irq, cpu_softirq, loadavg, used_memory, used_swap, created_at
          )
            
          SELECT
            vps_id, status, is_running, uptime, cpus, total_memory, total_swap,
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
            '#{t}'
          FROM vps_current_statuses WHERE vps_id = #{vps_id}"
      )
    end

    def reset_status(db, t, vps_id, vps)
      if vps[:last_status_id]
        sql = "UPDATE vps_current_statuses SET "

      else
        sql = "INSERT INTO vps_current_statuses SET vps_id = #{vps_id},"
      end

      sql += "
          status = #{vps[:skip] ? 0 : 1},
          total_memory = #{vps[:total_memory]},
          total_swap = #{vps[:total_swap]},
          cpus = #{vps[:cpus]},
          is_running = #{vps[:running] ? 1 : 0},
          update_count = 1,"
      
      if vps[:running] && !vps[:skip]
        cpu = vps[:cpu].to_percent

        sql += "
          uptime = #{vps[:uptime]},
          loadavg = #{vps[:loadavg]},
          process_count = #{vps[:nproc]},
          used_memory = #{vps[:used_memory]},
          used_swap = #{vps[:used_swap]},
          cpu_user = #{cpu[:user]},
          cpu_nice = #{cpu[:nice]},
          cpu_system = #{cpu[:system]},
          cpu_idle = #{cpu[:idle]},
          cpu_iowait = #{cpu[:iowait]},
          cpu_irq = #{cpu[:irq]},
          cpu_softirq = #{cpu[:softirq]},"

      else
        sql += "
          uptime = NULL, 
          loadavg = NULL,
          process_count = NULL,
          used_memory = NULL,
          used_swap = NULL,
          cpu_user = NULL,
          cpu_nice = NULL,
          cpu_system = NULL,
          cpu_idle = NULL,
          cpu_iowait = NULL,
          cpu_irq = NULL,
          cpu_softirq = NULL,"
      end
        
      sql += "
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

      sql += "created_at = '#{t}', updated_at = NULL "
      sql += "WHERE vps_id = #{vps_id}" if vps[:last_status_id]

      db.query(sql)
    end

    def update_status(db, t, vps_id, vps)
      sql = "UPDATE vps_current_statuses SET status = #{vps[:skip] ? 0 : 1},"
      
      if vps[:running] && !vps[:skip]
        cpu = vps[:cpu].to_percent

        sql += "
          uptime = #{vps[:uptime]},
          loadavg = #{vps[:loadavg]},
          process_count = #{vps[:nproc]},
          used_memory = #{vps[:used_memory]},
          used_swap = #{vps[:used_swap]},
          cpu_user = #{cpu[:user]},
          cpu_nice = #{cpu[:nice]},
          cpu_system = #{cpu[:system]},
          cpu_idle = #{cpu[:idle]},
          cpu_iowait = #{cpu[:iowait]},
          cpu_irq = #{cpu[:irq]},
          cpu_softirq = #{cpu[:softirq]},

          sum_loadavg = sum_loadavg + loadavg,
          sum_process_count = sum_process_count + process_count,
          sum_used_memory = sum_used_memory + used_memory,
          sum_used_swap = sum_used_swap + used_swap,
          sum_cpu_user = sum_cpu_user + cpu_user,
          sum_cpu_nice = sum_cpu_nice + cpu_nice,
          sum_cpu_system = sum_cpu_system + cpu_system,
          sum_cpu_idle = sum_cpu_idle + cpu_idle,
          sum_cpu_iowait = sum_cpu_iowait + cpu_iowait,
          sum_cpu_irq = sum_cpu_irq + cpu_irq,
          sum_cpu_softirq = sum_cpu_softirq + cpu_softirq,

          update_count = update_count + 1,
        "
      end

      sql += "updated_at = '#{t}' "
      sql += "WHERE vps_id = #{vps_id}"

      db.query(sql)
    end
  end
end
