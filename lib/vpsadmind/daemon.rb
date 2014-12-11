module VpsAdmind
  VERSION = '2.0.0-dev'
  DB_VERSION = 15

  EXIT_OK = 0
  EXIT_ERR = 1
  EXIT_STOP = 100
  EXIT_RESTART = 150
  EXIT_UPDATE = 200

  class Daemon
    include Utils::Log

    attr_reader :start_time, :export_console

    @@run = true
    @@exitstatus = EXIT_OK
    @@mutex = Mutex.new

    def initialize
      @db = Db.new
      @workers = {}
      @m_workers = Mutex.new
      @start_time = Time.new
      @export_console = false
      @cmd_counter = 0
      @threads = {}
    end

    def init
      update_status(true)

      node = Node.new
      node.init

      @fw = Firewall.new
      @fw.init(@db)

      @shaper = Shaper.new
      @shaper.init(@db)
    end

    def start
      check_db_version

      loop do
        sleep($CFG.get(:vpsadmin, :check_interval))

        run_threads

        catch (:next) do
          @m_workers.synchronize do
            @workers.delete_if do |wid, w|
              unless w.working?
                c = w.cmd
                c.save(@db)

                if @pause && w.cmd.id.to_i === @pause
                  pause!(true)
                end

                next true
              end

              false
            end

            throw :next if @workers.size >= ($CFG.get(:vpsadmin, :threads) + $CFG.get(:vpsadmin, :urgent_threads))

            @@mutex.synchronize do
              unless @@run
                if !@pause && @workers.empty?
                  exit(@@exitstatus)
                end

                throw :next
              end
            end

            do_commands
          end
        end

        $stdout.flush
        $stderr.flush
      end
    end

    def select_commands(db, limit = nil)
      limit ||= $CFG.get(:vpsadmin, :threads)

      db.query("SELECT * FROM (
								(SELECT *, 1 AS depencency_success FROM transactions
								WHERE t_done = 0 AND t_server = #{$CFG.get(:vpsadmin, :server_id)} AND t_depends_on IS NULL
								GROUP BY transaction_chain_id, t_priority, t_id)

								UNION ALL

								(SELECT t.*, d.t_success AS dependency_success
								FROM transactions t
								INNER JOIN transactions d ON t.t_depends_on = d.t_id
								WHERE
								t.t_done = 0
								AND d.t_done = 1
								AND t.t_server = #{$CFG.get(:vpsadmin, :server_id)}
								GROUP BY transaction_chain_id, t_priority, t_id)

								ORDER BY t_priority DESC, t_id ASC
							) tmp
							GROUP BY transaction_chain_id, t_priority
              ORDER BY t_priority DESC, t_id ASC
              LIMIT #{limit}")
    end

    def do_commands
      rs = select_commands(@db)

      rs.each_hash do |row|
        c = Command.new(row)

        unless row["depencency_success"].to_i > 0
          c.dependency_failed(@db)
          next
        end

        do_command(c)
      end
    end

    def do_command(cmd)
      wid = cmd.worker_id

      threads = $CFG.get(:vpsadmin, :threads)
      urgent = $CFG.get(:vpsadmin, :urgent_threads)

      if !@workers.has_key?(wid) && (@workers.size < threads || (cmd.urgent? && @workers.size < (threads+urgent)))
        @cmd_counter += 1
        @workers[wid] = Worker.new(cmd)
      end
    end

    def run_threads
      run_thread_unless_runs(:status) do
        loop do
          log 'Update status'

          update_status

          sleep($CFG.get(:vpsadmin, :status_interval))
        end
      end

      run_thread_unless_runs(:resources) do
        loop do
          log 'Update resources'

          update_resources

          sleep($CFG.get(:vpsadmin, :resources_interval))
        end
      end

      run_thread_unless_runs(:transfers) do
        loop do
          log 'Update transfers'

          update_transfers

          sleep($CFG.get(:vpsadmin, :transfers_interval))
        end
      end
    end

    def run_thread_unless_runs(name)
      if !@threads[name] || !@threads[name].alive?
        @threads[name] = Thread.new do
          yield
        end
      end
    end

    def update_all
      update_status(true)
      update_resources
    end

    def update_status(kernel = nil)
      node = Node.new
      system_load = node.load[5]
      server_id = $CFG.get(:vpsadmin, :server_id)

      my = Db.new
      my.prepared('INSERT INTO servers_status
                  SET server_id = ?, timestamp = UNIX_TIMESTAMP(NOW()), cpu_load = ?, daemon = ?, vpsadmin_version = ?
                  ON DUPLICATE KEY UPDATE
                  timestamp = UNIX_TIMESTAMP(NOW()), cpu_load = ?, daemon = ?, vpsadmin_version = ?',
                  server_id,
                  system_load, 0, VpsAdmind::VERSION,
                  system_load, 0, VpsAdmind::VERSION
      )

      unless kernel.nil?
        my.prepared('UPDATE servers_status SET kernel = ? WHERE server_id = ?', node.kernel, server_id)
      end

      my.close
    end

    def update_resources
      my = Db.new

      if $CFG.get(:vpsadmin, :update_vps_status)
        rs = my.query("SELECT vps_id FROM vps WHERE vps_server = #{$CFG.get(:vpsadmin, :server_id)}")

        rs.each_hash do |vps|
          ct = Vps.new(vps["vps_id"])
          ct.update_status(my)
        end
      end

      if $CFG.get(:storage, :update_status)
        Dataset.new.update_status
      end

      my.close
    end

    def update_transfers
      return unless $CFG.get(:vpsadmin, :track_transfers)

      Firewall.mutex.synchronize do
        my = Db.new
        fw = Firewall.new
        fw.update_traffic(my)
        my.close
      end
    end

    def start_em(console, remote)
      return if !console && !remote && !$CFG.get(:scheduler, :enabled)

      @export_console = console

      @em_thread = Thread.new do
        EventMachine.run do
          EventMachine.start_server($CFG.get(:console, :host), $CFG.get(:console, :port), VzServer) if console
          EventMachine.start_unix_domain_server($CFG.get(:remote, :socket), RemoteControl, self) if remote
        end
      end
    end

    def workers
      @m_workers.synchronize do
        yield(@workers)
      end
    end

    def check_db_version
      informed = false

      loop do
        @@mutex.synchronize do
          exit(@@exitstatus) unless @@run
        end

        rs = @db.query("SELECT cfg_value FROM sysconfig WHERE cfg_name = 'db_version'")
        raw_ver = rs.fetch_row.first

        if raw_ver == '"install"'
          log "Setting database version #{DB_VERSION}"
          @db.prepared("UPDATE sysconfig SET cfg_value=? WHERE cfg_name = 'db_version'", DB_VERSION)
          return
        end

        ver = raw_ver.to_i

        if VpsAdmind::DB_VERSION != ver
          unless informed
            log "Database version does not match: required #{VpsAdmind::DB_VERSION}, current #{ver}"
            $stdout.flush

            informed = true
          end

          sleep(10)
        else
          return
        end
      end
    end

    def pause(t = true)
      @m_workers.synchronize do
        pause!(t)
      end
    end

    def pause!(t = true)
      @pause = t

      if @pause === true
        @@mutex.synchronize do
          @@run = false
        end
      end
    end

    def resume
      @m_workers.synchronize do
        @@run = true
        @pause = nil
      end
    end

    def run?
      @@run
    end

    def paused?
      @pause
    end

    def exitstatus
      @@exitstatus
    end

    def Daemon.safe_exit(status)
      @@mutex.synchronize do
        @@run = false
        @@exitstatus = status
      end
    end
  end
end
