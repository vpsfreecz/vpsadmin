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
      @start_time = Time.new
      @export_console = false
      @cmd_counter = 0
      @threads = {}
      @mount_reporter = MountReporter.new
      @delayed_mounter = DelayedMounter.new # FIXME: call stop?
      @remote_control = RemoteControl.new(self) if remote
      @node_status = NodeStatus.new
      @vps_status = VpsStatus.new
      @fw = Firewall.instance
      Worker.instance
    end

    def init(do_init)
      if do_init
        @node_status.init(@db)
        @node_status.update(@db)

        node = Node.new
        node.init
      end

      @mount_reporter.start
      @delayed_mounter.start
      @remote_control && @remote_control.start

      if do_init
        @fw.init(@db)

        @shaper = Shaper.new
        @shaper.init(@db)
      end
    end

    def start
      loop do
        sleep(1)

        if @@run
          run_threads
        else
          break if can_stop?
        end

        $stdout.flush
        $stderr.flush
      end
    end

    def run_threads
      run_thread_unless_runs(:status) do
        loop do
          log(:info, :regular, 'Update status')

          @node_status.update

          sleep($CFG.get(:vpsadmin, :status_interval))
        end
      end

      run_thread_unless_runs(:vps_status) do
        loop do
          if $CFG.get(:vpsadmin, :update_vps_status)
            log(:info, :regular, 'Update VPS resources')

            my = Db.new
            @vps_status.update(my)
            my.close
          end

          sleep($CFG.get(:vpsadmin, :vps_status_interval))
        end
      end

      run_thread_unless_runs(:storage_status) do
        loop do
          if $CFG.get(:storage, :update_status)
            log(:info, :regular, 'Update storage resources')

            my = Db.new
            StorageStatus.update(my)
            my.close
          end

          sleep($CFG.get(:vpsadmin, :storage_status_interval))
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
      my = Db.new

      @node_status.update(my)

      if $CFG.get(:vpsadmin, :update_vps_status)
        @vps_status.update(my)
      end

      if $CFG.get(:storage, :update_status)
        StorageStatus.update(my)
      end

      my.close
    end

    def update_transfers
      return unless $CFG.get(:vpsadmin, :track_transfers)

      Firewall.synchronize do |fw|
        my = Db.new
        fw.accounting.update_traffic(my)
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

    def can_stop?
      Worker.empty? && TransactionBlocker.empty?
    end

    def run?
      @@run
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
