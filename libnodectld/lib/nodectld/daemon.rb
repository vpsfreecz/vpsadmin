require 'eventmachine'
require 'libosctl'
require 'nodectld/db'
require 'nodectld/command'
require 'nodectld/mount_reporter'
require 'nodectld/delayed_mounter'
require 'nodectld/remote_control'
require 'nodectld/node_status'
require 'nodectld/vps_status'
require 'nodectld/storage_status'
require 'nodectld/firewall'
require 'nodectld/shaper'
require 'nodectld/ct_top'
require 'nodectld/ct_monitor'
require 'thread'

module NodeCtld
  EXIT_OK = 0
  EXIT_ERR = 1
  EXIT_STOP = 100
  EXIT_RESTART = 150
  EXIT_UPDATE = 200

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

    attr_reader :start_time, :export_console, :delayed_mounter, :ct_top

    def initialize
      self.class.instance = self
      @db = Db.new
      @start_time = Time.new
      @export_console = false
      @cmd_counter = 0
      @threads = {}
      @blockers_mutex = Mutex.new
      @chain_blockers = {}
      @mount_reporter = MountReporter.new
      @delayed_mounter = DelayedMounter.new # FIXME: call stop?
      @remote_control = RemoteControl.new(self)
      @node_status = NodeStatus.new
      @vps_status = VpsStatus.new
      @fw = Firewall.instance
      Shaper.instance
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
      @remote_control.start

      if do_init
        @fw.init(@db)
        Shaper.init(@db)
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
        if $CFG.get(:vpsadmin, :update_vps_status)
          @ct_top = CtTop.new
          @ct_top.monitor($CFG.get(:vpsadmin, :vps_status_interval)) do |data|
            @vps_status.update(data[:containers])
          end

        else
          @ct_top.stop if @ct_top
          @ct_top = nil
        end
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
        # TODO
        # @vps_status.update(my)
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
      Worker.empty? && @blockers_mutex.synchronize { @chain_blockers.empty? }
    end

    def run?
      @@run
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
