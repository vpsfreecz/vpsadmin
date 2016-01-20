module VpsAdmind
  EXIT_OK = 0
  EXIT_ERR = 1
  EXIT_STOP = 100
  EXIT_RESTART = 150
  EXIT_UPDATE = 200

  class Daemon
    include Utils::Log

    attr_reader :start_time, :export_console, :delayed_mounter

    @@run = true
    @@exitstatus = EXIT_OK
    @@mutex = Mutex.new

    class << self
      attr_accessor :instance
    end

    def initialize(remote)
      self.class.instance = self
      @db = Db.new
      @m_workers = Mutex.new
      @start_time = Time.new
      @export_console = false
      @cmd_counter = 0
      @threads = {}
      @blockers_mutex = Mutex.new
      @chain_blockers = {}
      @queues = Queues.new(self)
      @mount_reporter = MountReporter.new
      @delayed_mounter = DelayedMounter.new # FIXME: call stop?
      @remote_control = RemoteControl.new(self) if remote
    end

    def init(do_init)
      if do_init
        update_status(true)

        node = Node.new
        node.init
      end

      @mount_reporter.start
      @delayed_mounter.start
      @remote_control && @remote_control.start
     
      if do_init
        @fw = Firewall.new
        @fw.init(@db)

        @shaper = Shaper.new
        @shaper.init(@db)
      end
    end

    def start
      loop do
        sleep($CFG.get(:vpsadmin, :check_interval))

        run_threads

        catch (:next) do
          @m_workers.synchronize do
            @queues.each_value do |queue|
              queue.delete_if do |wid, w|
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
            end
            
            throw :next if @queues.full?

            @@mutex.synchronize do
              unless @@run
                exit(@@exitstatus) if can_stop?

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
      limit ||= @queues.total_limit

      db.union do |u|
        # Transactions for execution
        u.query("SELECT * FROM (
                  (SELECT t1.*, 1 AS depencency_success,
                          ch1.state AS chain_state, ch1.progress AS chain_progress,
                          ch1.size AS chain_size
                  FROM transactions t1
                  INNER JOIN transaction_chains ch1 ON ch1.id = t1.transaction_chain_id
                  WHERE
                      t_done = 0 AND t_server = #{$CFG.get(:vpsadmin, :server_id)}
                      AND ch1.state = 1
                      AND t_depends_on IS NULL
                  GROUP BY transaction_chain_id, t_priority, t_id)

                  UNION ALL

                  (SELECT t2.*, d.t_success AS dependency_success,
                          ch2.state AS chain_state, ch2.progress AS chain_progress,
                          ch2.size AS chain_size
                  FROM transactions t2
                  INNER JOIN transactions d ON t2.t_depends_on = d.t_id
                  INNER JOIN transaction_chains ch2 ON ch2.id = t2.transaction_chain_id
                  WHERE
                      t2.t_done = 0
                      AND d.t_done = 1
                      AND t2.t_server = #{$CFG.get(:vpsadmin, :server_id)}
                      AND ch2.state = 1
                      GROUP BY transaction_chain_id, t_priority, t_id)

                  ORDER BY t_priority DESC, t_id ASC
                ) tmp
                GROUP BY transaction_chain_id, t_priority
                ORDER BY t_priority DESC, t_id ASC
                LIMIT #{limit}")

        # Transactions for rollback.
        # It is the same query, only transactions are in reverse order.
        u.query("SELECT * FROM (
                  (SELECT d.*,
                          ch2.state AS chain_state, ch2.progress AS chain_progress,
                          ch2.size AS chain_size, ch2.urgent_rollback AS chain_urgent_rollback
                  FROM transactions t2
                  INNER JOIN transactions d ON t2.t_depends_on = d.t_id
                  INNER JOIN transaction_chains ch2 ON ch2.id = t2.transaction_chain_id
                  WHERE
                      t2.t_done = 2
                      AND d.t_success IN (1,2)
                      AND d.t_done = 1
                      AND d.t_server = #{$CFG.get(:vpsadmin, :server_id)}
                      AND ch2.state = 3)

                  ORDER BY t_priority DESC, t_id DESC
                ) tmp
                GROUP BY transaction_chain_id, t_priority
                ORDER BY t_priority DESC, t_id DESC
                LIMIT #{limit}")
      end
    end

    def do_commands
      rs = select_commands(@db)

      rs.each_hash do |row|
        c = Command.new(row)

        do_command(c)
      end
    end

    def do_command(cmd)
      wid = cmd.worker_id

      threads = $CFG.get(:vpsadmin, :threads)
      urgent = $CFG.get(:vpsadmin, :urgent_threads)

      if chain_blocked?(cmd.chain_id)
        log(:debug, cmd, 'Transaction is blocked - waiting for child process to finish')
        return
      end

      if @queues.execute(cmd)
        @cmd_counter += 1
      end
    end

    def run_threads
      run_thread_unless_runs(:status) do
        loop do
          log(:info, :regular, 'Update status')

          update_status

          sleep($CFG.get(:vpsadmin, :status_interval))
        end
      end

      run_thread_unless_runs(:resources) do
        loop do
          log(:info, :regular, 'Update resources')

          update_resources

          sleep($CFG.get(:vpsadmin, :resources_interval))
        end
      end

      run_thread_unless_runs(:transfers) do
        loop do
          log(:info, :regular, 'Update transfers')

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

      t = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      my = Db.new
      my.prepared('INSERT INTO servers_status
                  SET server_id = ?, created_at = ?, cpu_load = ?, daemon = ?, vpsadmin_version = ?
                  ON DUPLICATE KEY UPDATE
                  created_at = ?, cpu_load = ?, daemon = ?, vpsadmin_version = ?',
                  server_id,
                  t, system_load, 0, VpsAdmind::VERSION,
                  t, system_load, 0, VpsAdmind::VERSION
      )

      unless kernel.nil?
        my.prepared('UPDATE servers_status SET kernel = ? WHERE server_id = ?', node.kernel, server_id)
      end

      my.close
    end

    def update_resources
      my = Db.new

      if $CFG.get(:vpsadmin, :update_vps_status)
        rs = my.query(
            "SELECT vps_id, manage_hostname
            FROM vps
            WHERE
              vps_server = #{$CFG.get(:vpsadmin, :server_id)}
              AND object_state < 3"
        )

        rs.each_hash do |vps|
          ct = Vps.new(vps["vps_id"])
          ct.update_status(my, vps["manage_hostname"].to_i == 0)
        end
      end

      StorageStatus.update(my) if $CFG.get(:storage, :update_status)

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

    def start_em(console)
      return if !console

      @export_console = console

      @em_thread = Thread.new do
        EventMachine.run do
          if console
            EventMachine.start_server(
                $CFG.get(:console, :host),
                $CFG.get(:console, :port),
                Console::Server
            )
          end
        end
      end
    end

    def queues
      @m_workers.synchronize do
        yield(@queues)
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

    def can_stop?
      @blockers_mutex.synchronize do
        !@pause && @queues.empty? && @chain_blockers.empty?
      end
    end

    def exitstatus
      @@exitstatus
    end

    def chain_blocked?(chain_id)
      @blockers_mutex.synchronize do
        @chain_blockers.has_key?(chain_id)
      end
    end

    def block_chain(chain_id, pid)
      @blockers_mutex.synchronize do
        @chain_blockers[chain_id] ||= []
        @chain_blockers[chain_id] << pid

        Thread.new do
          log(:debug, :daemon, "Chain #{chain_id} is waiting for subprocess #{pid} to finish")
          Process.wait(pid)
          subprocess_finished(chain_id, pid)
        end
      end
    end

    def chain_blockers
      @blockers_mutex.synchronize do
        yield(@chain_blockers)
      end
    end

    def subprocess_finished(chain_id, pid)
      @blockers_mutex.synchronize do
        log(:debug, :daemon, "Subprocess #{pid} of chain #{chain_id} finished")
        @chain_blockers[chain_id].delete(pid)
        @chain_blockers.delete(chain_id) if @chain_blockers[chain_id].empty?
      end
    end

    def Daemon.safe_exit(status)
      @@mutex.synchronize do
        @@run = false
        @@exitstatus = status
      end
    end

    def self.register_subprocess(chain_id, pid)
      instance.block_chain(chain_id, pid)
    end
  end
end
