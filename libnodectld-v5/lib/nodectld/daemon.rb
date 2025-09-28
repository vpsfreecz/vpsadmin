require 'libosctl'
require 'nodectld/db'
require 'nodectld/command'
require 'nodectld/queues'
require 'nodectld/remote_control'
require 'nodectld/node_status'
require 'nodectld/vps_status'
require 'nodectld/storage_status'
require 'nodectld/shaper'
require 'nodectld/ct_monitor'

module NodeCtld
  EXIT_OK = 0
  EXIT_ERR = 1
  EXIT_STOP = 100
  EXIT_RESTART = 150

  class Daemon
    include OsCtl::Lib::Utils::Log

    @@run = true
    @@exitstatus = EXIT_OK
    @@mutex = Mutex.new

    class << self
      attr_accessor :instance

      def safe_exit(status)
        @@mutex.synchronize do
          @@run = false
          @@exitstatus = status
        end
      end

      def register_subprocess(chain_id, pid)
        instance.block_chain(chain_id, pid)
      end
    end

    attr_reader :start_time, :node, :console, :queues, :last_transaction_check

    def initialize
      self.class.instance = self
      @init = false
      @start_time = Time.new
      @cmd_counter = 0
      @threads = {}
      @blockers_mutex = Mutex.new
      @chain_blockers = {}
      @queues = Queues.new(self)
      @remote_control = RemoteControl.new(self)
      NodeBunny.connect
      @node_status = NodeStatus.new
      @storage_status = StorageStatus.new
      @vps_status = VpsStatus.new
      @kernel_log = KernelLog::Parser.new
      @exporter = Exporter.new(self)
      @console = Console::Server.new
      @dns_status = DnsStatus.new if $CFG.get(:vpsadmin, :type) == :dns_server
      NetAccounting.instance
      Shaper.instance
      TransactionVerifier.instance
    end

    def init
      @remote_control.start

      NetAccounting.init
      Shaper.init_node if $CFG.get(:shaper, :enable)
      Export.init if $CFG.get(:exports, :enable)

      @node_status.update

      @kernel_log.start if $CFG.get(:kernel_log, :enable)
      @exporter.start if $CFG.get(:exporter, :enable)
      VpsSshHostKeys.instance
      VpsOsRelease.instance
      @storage_status.start if @storage_status.enable?
      @console.start if $CFG.get(:console, :enable)
      @dns_status.start if $CFG.get(:vpsadmin, :type) == :dns_server

      @init = true
    end

    def start
      @cmd_db = nil
      @cmd_db_created = nil

      loop do
        sleep($CFG.get(:vpsadmin, :check_interval))

        run_threads
        work

        $stdout.flush
        $stderr.flush
      end
    end

    def work
      @queues.each_value do |queue|
        queue.delete_if do |_wid, w|
          unless w.working?
            c = w.cmd
            Db.open { |db| c.save(db) }

            pause!(true) if @pause && w.cmd.id.to_i === @pause

            next true
          end

          false
        end
      end

      return if @queues.full?

      @@mutex.synchronize do
        unless @@run
          exit(@@exitstatus) if can_stop?
          return
        end
      end

      now = Time.now

      if @cmd_db.nil? || @cmd_db_created + (5 * 60) <= now
        @cmd_db.close if @cmd_db
        @cmd_db = Db.new
        @cmd_db_created = Time.now
      end

      begin
        do_commands(@cmd_db)
      rescue TransactionCheckError
        log(:warn, :daemon, 'Failed to check transactions, resetting database connection')
        @cmd_db.close
        @cmd_db = nil
        sleep(10)
      end
    end

    def check_commands?(db)
      update_rs = db.prepared(
        'SELECT update_time
        FROM information_schema.tables
        WHERE table_schema = ? AND table_name = ?',
        $CFG.get(:db, :name),
        'transactions'
      ).get

      @last_transaction_check = Time.now

      # Sometimes, update_rs is nil, i.e. no row is returned. It's not clear
      # how this could happen, but handle it to avoid a crash.
      raise TransactionCheckError if update_rs.nil?

      @skipped_transaction_checks ||= 0

      current_transaction_update = @last_transaction_update
      @last_transaction_update = update_rs['update_time']

      if current_transaction_update.nil? || @last_transaction_update.nil?
        true

      elsif @skipped_transaction_checks > (60 / $CFG.get(:vpsadmin, :check_interval))
        @skipped_transaction_checks = 0
        true

      elsif current_transaction_update >= update_rs['update_time']
        @skipped_transaction_checks += 1
        false

      else # rubocop:disable Lint/DuplicateBranch
        @skipped_transaction_checks = 0
        true
      end
    end

    def select_commands(db, limit = nil)
      limit ||= @queues.total_limit

      db.union do |u|
        # Transactions for execution
        u.query(
          "SELECT * FROM (
            (SELECT t1.*, 1 AS depencency_success,
                    ch1.state AS chain_state, ch1.progress AS chain_progress,
                    ch1.size AS chain_size
            FROM transactions t1
            INNER JOIN transaction_chains ch1 ON ch1.id = t1.transaction_chain_id
            WHERE
                done = 0 AND node_id = #{$CFG.get(:vpsadmin, :node_id)}
                AND ch1.state = 1
                AND depends_on_id IS NULL
            GROUP BY transaction_chain_id, priority, t1.id)

            UNION ALL

            (SELECT t2.*, d.status AS dependency_success,
                    ch2.state AS chain_state, ch2.progress AS chain_progress,
                    ch2.size AS chain_size
            FROM transactions t2
            INNER JOIN transactions d ON t2.depends_on_id = d.id
            INNER JOIN transaction_chains ch2 ON ch2.id = t2.transaction_chain_id
            WHERE
                t2.done = 0
                AND d.done = 1
                AND t2.node_id = #{$CFG.get(:vpsadmin, :node_id)}
                AND ch2.state = 1
                GROUP BY transaction_chain_id, priority, id)

            ORDER BY priority DESC, id ASC
          ) tmp
          GROUP BY transaction_chain_id, priority
          ORDER BY priority DESC, id ASC
          LIMIT #{limit}"
        )

        # Transactions for rollback.
        # It is the same query, only transactions are in reverse order.
        u.query(
          "SELECT * FROM (
            (SELECT d.*,
                    ch2.state AS chain_state, ch2.progress AS chain_progress,
                    ch2.size AS chain_size, ch2.urgent_rollback AS chain_urgent_rollback
            FROM transactions t2
            INNER JOIN transactions d ON t2.depends_on_id = d.id
            INNER JOIN transaction_chains ch2 ON ch2.id = t2.transaction_chain_id
            WHERE
                t2.done = 2
                AND d.status IN (1,2)
                AND d.done = 1
                AND d.node_id = #{$CFG.get(:vpsadmin, :node_id)}
                AND ch2.state = 3)

            ORDER BY priority DESC, id DESC
          ) tmp
          GROUP BY transaction_chain_id, priority
          ORDER BY priority DESC, id DESC
          LIMIT #{limit}"
        )
      end
    end

    def do_commands(db)
      return unless check_commands?(db)

      rs = select_commands(db)
      cmds = []

      # Once again, sometimes we get invalid results
      rs.each do |row|
        raise TransactionCheckError if row['queue'].nil?

        cmds << row
      end

      cmds.each do |row|
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

      return unless @queues.execute(cmd)

      @cmd_counter += 1
    end

    def run_threads
      run_thread_unless_runs(:queues_prune) do
        loop do
          n = 0

          db = Db.new
          n = @queues.prune_reservations(db)
          db.close

          log(:info, :queues, "Released #{n} slot reservations") if n > 0

          sleep($CFG.get(:vpsadmin, :queues_reservation_prune_interval))
        end
      end

      run_thread_unless_runs(:status) do
        loop do
          log(:info, :regular, 'Update status')

          @node_status.update

          sleep($CFG.get(:vpsadmin, :status_interval))
        end
      end

      run_thread_unless_runs(:vps_status) do
        # TODO: implement VPS statuses with libvirt
      end

      run_thread_unless_runs(:vps_monitor) do
        if $CFG.get(:vpsadmin, :update_vps_status)
          @ct_monitor = CtMonitor.new
          @ct_monitor.start

        else
          @ct_monitor.stop if @ct_monitor
          @ct_monitor = nil
        end
      end
    end

    def run_thread_unless_runs(name, &)
      return unless !@threads[name] || !@threads[name].alive?

      @threads[name] = Thread.new(&)
    end

    def update_all
      @node_status.update

      if $CFG.get(:vpsadmin, :update_vps_status)
        # TODO
        # @vps_status.update
      end

      return unless $CFG.get(:storage, :update_status)

      @storage_status.update
    end

    def pause(t = true)
      pause!(t)
    end

    def pause!(t = true)
      @pause = t

      return unless @pause === true

      @@mutex.synchronize do
        @@run = false
      end
    end

    def resume
      @@mutex.synchronize do
        @@run = true
        @pause = nil
        @last_transaction_update = nil
      end
    end

    def initialized?
      @init
    end

    def run?
      @@run
    end

    def paused?
      @pause
    end

    def can_stop?
      !@pause && @queues.empty? && @blockers_mutex.synchronize { @chain_blockers.empty? }
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
  end
end
