module VpsAdmind
  class VpsStatus
    include Utils::Log
    include Utils::System
    include Utils::Vz
    include Utils::Vps

    def initialize(vps_ids = nil)
      @vps_ids = vps_ids
    end

    def update(db)
      db_vpses = {}

      fetch_vpses(db).each_hash do |row|
        db_vpses[ row['vps_id'].to_i ] = {
            :read_hostname => row['manage_hostname'].to_i == 0
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

        disk_str = syscmd("#{$CFG.get(:bin, :df)} -k #{ve_private(vps[:veid])}")[:output]
        db_vps[:disk] = disk_str.split("\n")[1].split(" ")[2].to_i / 1024
       
        if db_vps[:running]
          db_vps[:loadavg] = vps[:laverage][1]

          if db_vps[:read_hostname] 
            db_vps[:hostname] = vzctl(:exec, vps[:veid], 'hostname')[:output].strip
          end
        end
      end

      # Initial run to make sure that all libraries are loaded in memory and
      # consequent calls will be as fast as possible.
      db_vpses.each do |vps_id, vps|
        next if !vps[:exists] || !vps[:running]
        
        vzctl(:exec, vps_id, 'cat /proc/stat > /dev/null')
      end

      # First CPU measurement
      db_vpses.each do |vps_id, vps|
        next if !vps[:exists] || !vps[:running]

        vps[:cpu].measure_once(vzctl(:exec, vps_id, 'cat /proc/stat')[:output])
      end

      sleep(0.2)

      # Final CPU measurement
      db_vpses.each do |vps_id, vps|
        next if !vps[:exists] || !vps[:running]

        vps[:cpu].measure_once(vzctl(:exec, vps_id, 'cat /proc/stat')[:output])
      end

      # Save results to db
      db_vpses.each do |vps_id, vps|
        next unless vps[:exists]
       
        t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

        sql = "INSERT INTO vps_statuses SET
            vps_id = #{vps_id},
            is_running = #{vps[:running] ? 1 : 0},
            cpus = #{vps[:cpus]},
            total_memory = #{vps[:total_memory]},
            total_swap = #{vps[:total_swap]},
            used_diskspace = #{vps[:disk]},"
            
        if vps[:running]
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
            cpu_guest = #{cpu[:guest]},
          "
        end

        sql += "created_at = '#{t}'"
       
        db.query(sql)

        if vps[:hostname]
          db.prepared(
              'UPDATE vps SET vps_status_id = ?, vps_hostname = ? WHERE vps_id = ?',
              db.insert_id, vps[:hostname], vps_id
          )

        else
          db.prepared(
              'UPDATE vps SET vps_status_id = ? WHERE vps_id = ?',
              db.insert_id, vps_id
          )
        end
      end
    end

    protected
    def fetch_vpses(db)
      sql = "
          SELECT vps_id, manage_hostname
          FROM vps
          WHERE
            vps_server = #{$CFG.get(:vpsadmin, :server_id)}
            AND object_state < 3"

      if @vps_ids
        sql += " AND vps_id IN (#{@vps_ids.join(',')})"
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
        syscmd(cmd)[:output],
        :symbolize_names => true
      )
    end
  end
end
