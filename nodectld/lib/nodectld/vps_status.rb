require 'etc'
require 'time'

module NodeCtld
  class VpsStatus
    class Entry
      attr_reader :id, :read_hostname, :last_status_id, :last_is_running,
        :status_time, :cpus, :last_total_memory
      attr_accessor :exists, :running, :hostname, :uptime, :cpu_usage, :memory, :nproc

      # @param row [Hash] row from databse table `vpses`
      def initialize(row)
        @id = row['id'].to_s
        @read_hostname = row['manage_hostname'].to_i == 0
        @last_status_id = row['status_id'] && row['status_id'].to_i
        @last_is_running = row['is_running'].to_i == 1
        @status_time = row['created_at']
        @cpus = row['cpus'].to_i
      end

      alias_method :read_hostname?, :read_hostname
      alias_method :exists?, :exists
      alias_method :running?, :running

      def skip
        @skip = true
      end

      def skip?
        @skip
      end
    end

    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl
    include Utils::Vps

    @@mutex = Mutex.new

    def initialize
      @tics_per_sec = Etc.sysconf(Etc::SC_CLK_TCK).to_i
    end

    # If `db_in` is not provided, new connection to DB is opened and closed
    # when the status is updated.
    #
    # @param top_data [Hash] data from osctl ct top
    # @param db_in [NodeCtld::Db]
    def update(top_data, db_in = nil)
      @@mutex.synchronize do
        @top_data = top_data
        @host_uptime = SystemProbes::Uptime.new.uptime

        db = db_in || Db.new
        safe_update(db)
        db.close unless db_in
      end
    end

    def safe_update(db)
      db_vpses = {}

      fetch_vpses(db).each do |row|
        ent = Entry.new(row)
        db_vpses[ent.id.to_s] = ent
      end

      ct_list.each do |vps|
        _, db_vps = db_vpses.detect { |k, v| k == vps[:id] }
        next unless db_vps

        db_vps.exists = true
        db_vps.running = vps[:state] == 'running'

        if db_vps.running?
          # Find matching stats from ct top
          apply_usage_stats(db_vps)

          run_or_skip(db_vps) do
            db_vps.uptime = read_uptime(vps[:init_pid])
          end

          # Read hostname if it isn't managed by vpsAdmin
          if db_vps.read_hostname?
            run_or_skip(db_vps) do
              db_vps.hostname = osctl(:exec, vps[:id], 'hostname')[:output].strip
            end

            if !db_vps.hostname || db_vps.hostname.empty?
              db_vps.hostname = 'unable to read'
            end
          end
        end
      end

      # Save results to db
      db_vpses.each do |vps_id, vps|
        next unless vps.exists?

        t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

        # The VPS is not running
        if !vps.running? && vps.last_status_id && !vps.last_is_running
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

        if vps.hostname
          db.prepared(
            'UPDATE vpses SET hostname = ? WHERE id = ?',
            vps.hostname, vps_id
          )
        end
      end

    rescue SystemCommandFailed => e
      log(:fatal, :vps_status, e.message)
    end

    protected
    def fetch_vpses(db)
      sql = "
        SELECT vpses.id, vpses.manage_hostname, st.id AS status_id, st.is_running,
               cru.value AS cpus, st.total_memory, st.created_at
        FROM vpses
        LEFT JOIN vps_current_statuses st ON st.vps_id = vpses.id
        INNER JOIN user_cluster_resources ucr ON ucr.user_id = vpses.user_id
        INNER JOIN cluster_resources cr ON cr.id = ucr.cluster_resource_id
        INNER JOIN cluster_resource_uses cru ON cru.user_cluster_resource_id = ucr.id
        WHERE
          vpses.node_id = #{$CFG.get(:vpsadmin, :node_id)}
          AND vpses.object_state < 3
          AND cr.name = 'cpu'
          AND cru.class_name = 'Vps'
          AND cru.row_id = vpses.id
          AND cru.confirmed = 1"

      db.query(sql)
    end

    def ct_list
      osctl_parse(%i(ct ls), [], output: 'pool,id,state,init_pid')
    end

    def run_or_skip(vps)
      yield

    rescue SystemCommandFailed => e
      log(:warn, :vps, e.message)
      vps.skip
    end

    def state_changed?(vps)
      vps.running? != vps.last_is_running
    end

    def status_expired?(vps)
      (vps.status_time + $CFG.get(:vpsadmin, :vps_status_log_interval)) < Time.now.utc
    end

    def apply_usage_stats(vps)
      st = @top_data.detect { |ct| ct[:id] == vps.id }
      return unless st

      vps.cpu_usage = st[:cpu_usage] / vps.cpus

      vps.memory = st[:memory] / 1024 / 1024
      vps.nproc = st[:nproc]
    end

    # Read the container's uptime
    #
    # The uptime of the container can be thought of as the time since its
    # init process has started. Process start time can be found in
    # `/proc/<pid>/stat`, the 22nd field, see proc(5). The value is stored
    # in clock ticks since the system boot, so we divide that by ticks per
    # second, and substract it from the host's uptime.
    #
    # @param init_pid [String,Integer]
    def read_uptime(init_pid)
      f = File.open(File.join('/proc', init_pid.to_s, 'stat'), 'r')
      str = f.readline.strip
      f.close

      @host_uptime - (str.split(' ')[21].to_i / @tics_per_sec)
    end

    def log_status(db, t, vps_id)
      db.query(
        "INSERT INTO vps_statuses (
          vps_id, status, is_running, uptime, cpus, total_memory, total_swap,
          process_count, cpu_idle, used_memory, created_at
        )

        SELECT
          vps_id, status, is_running, uptime, cpus, total_memory, total_swap,
          sum_process_count / update_count,
          sum_cpu_idle / update_count,
          sum_used_memory / update_count,
          '#{t}'
        FROM vps_current_statuses WHERE vps_id = #{vps_id}"
      )
    end

    def reset_status(db, t, vps_id, vps)
      if vps.last_status_id
        sql = "UPDATE vps_current_statuses SET "

      else
        sql = "INSERT INTO vps_current_statuses SET vps_id = #{vps_id},"
      end

      sql += "
          status = #{vps.skip? ? 0 : 1},
          is_running = #{vps.running? ? 1 : 0},
          update_count = 1,"

      if vps.running? && !vps.skip?
        sql += "
          uptime = #{vps.uptime},
          process_count = #{vps.nproc},
          used_memory = #{vps.memory},
          cpu_idle = #{100.0 - vps.cpu_usage},"

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
      sql += "WHERE vps_id = #{vps_id}" if vps.last_status_id

      db.query(sql)
    end

    def update_status(db, t, vps_id, vps)
      sql = "UPDATE vps_current_statuses SET status = #{vps.skip? ? 0 : 1},"

      if vps.running? && !vps.skip?
        sql += "
          uptime = #{vps.uptime},
          process_count = #{vps.nproc},
          used_memory = #{vps.memory},
          cpu_idle = #{100.0 - vps.cpu_usage},

          sum_process_count = sum_process_count + process_count,
          sum_used_memory = sum_used_memory + used_memory,
          sum_cpu_idle = sum_cpu_idle + cpu_idle,

          update_count = update_count + 1,
        "
      end

      sql += "updated_at = '#{t}' "
      sql += "WHERE vps_id = #{vps_id}"

      db.query(sql)
    end
  end
end
