require 'optparse'
require 'libosctl'
require 'nodectld/config'
require 'nodectld/daemon'
require 'nodectld/remote_control'

module NodeCtld
  class Cli
    include OsCtl::Lib::Utils::Log

    def self.run
      new.run
    end

    def run
      options = {
        config: '/etc/vpsadmin/nodectld.yml',
        check: false,
        logger: :stdout,
        wrapper: true,
        watchdog: true
      }

      OptionParser.new do |opts|
        opts.on('-c', '--config [CONFIG FILE]', 'Config file') do |cfg|
          options[:config] = cfg
        end

        opts.on('-k', '--check', 'Check config file syntax') do
          options[:check] = true
        end

        opts.on('-l', '--log LOGGER', %w[syslog stdout]) do |v|
          options[:logger] = v.to_sym
        end

        opts.on(
          '--log-facility FACILITY',
          'Syslog facility, see man syslog(3), lowercase without LOG_ prefix'
        ) do |v|
          options[:log_facility] = v
        end

        opts.on(
          '-w', '--[no-]wrapper',
          "Run script in wrapper or not - auto restart won't work"
        ) do |w|
          options[:wrapper] = w
        end

        opts.on('--[no-]watchdog', 'Run watchdog') do |v|
          opts[:watchdog] = v
        end

        opts.on_tail('-h', '--help', 'Show this message') do
          puts opts
          exit
        end
      end.parse!

      if options[:check]
        c = NodeCtld::AppConfig.new(options[:config])
        puts 'Config seems ok' if c.load
        exit
      end

      executable = File.expand_path($0)

      OsCtl::Lib::Logger.setup(options[:logger], facility: options[:log_facility])

      # Load config
      $CFG = NodeCtld::AppConfig.new(options[:config])
      exit(false) unless $CFG.load(false)

      if options[:wrapper]
        log('nodectld wrapper starting')
        run_wrapper(watchdog: options[:watchdog])
        return
      end

      run_daemon
    end

    protected

    def run_wrapper(watchdog:)
      @stop = false
      @stop_queue = OsCtl::Lib::Queue.new
      @watchdog_watcher_queue = OsCtl::Lib::Queue.new
      @watchdog_worker_queue = OsCtl::Lib::Queue.new

      loop do
        r, w = IO.pipe

        pid = Process.fork do
          $stdout.reopen(w)
          $stderr.reopen(w)
          r.close

          run_daemon
        end

        w.close

        Signal.trap('CHLD') do
          next if r.nil?

          r.close
          r = nil
        end

        %w[TERM INT].each do |sig|
          Signal.trap(sig) do
            @stop = true
            @stop_thread = Thread.new { stop_daemon(pid) }
          end
        end

        Signal.trap('HUP') do
          Process.kill('HUP', pid)
        end

        if watchdog
          @watchdog_watcher_thread = Thread.new { run_watchdog_watcher(pid) }
          @watchdog_worker_thread = Thread.new { run_watchdog_worker }
        end

        begin
          r.each do |line|
            log(:unknown, line)
          end
        rescue IOError
          r = nil
        end

        Process.waitpid(pid)
        @stop_queue << pid

        if watchdog
          [@watchdog_watcher_queue, @watchdog_worker_queue].each { |q| q << :stop }
          [@watchdog_watcher_thread, @watchdog_worker_thread].each(&:join)
        end

        if @stop
          @stop_thread.join if @stop_thread
          return
        end

        case $?.exitstatus
        when NodeCtld::EXIT_OK, NodeCtld::EXIT_STOP
          log 'Stopping daemon'
          exit

        when NodeCtld::EXIT_RESTART
          log 'Restarting daemon'
          r.close if r
          next

        else
          log "Daemon crashed with exit status #{$?.exitstatus}"
          exit(false)
        end
      end
    end

    def run_daemon
      $CFG.load_db_settings

      log(:info, :init, 'nodectld starting')

      Thread.abort_on_exception = true
      nodectld = NodeCtld::Daemon.new
      nodectld.init
      nodectld.start
    end

    def stop_daemon(pid)
      log 'Killing daemon'
      Process.kill('TERM', pid)

      v = @stop_queue.pop(timeout: 60)
      return if v == pid

      log 'Sending SIGKILL'
      Process.kill('KILL', pid)
    end

    def run_watchdog_watcher(pid)
      timeout = 90
      missed = 0
      limit = 900

      loop do
        v = @watchdog_watcher_queue.pop(timeout:)

        if v == :stop
          break
        elsif v == :alive
          if missed > 0
            log "Watchdog: daemon responded after #{missed}/#{limit} seconds"
          end

          missed = 0
          next
        end

        missed += timeout

        log "Watchdog: Daemon is unresponsive for #{missed}/#{limit} seconds"
        next if missed < limit

        log 'Watchdog: Daemon did not send status in time, restarting'
        @stop = true
        stop_daemon(pid)
      end
    end

    def run_watchdog_worker
      loop do
        v = @watchdog_worker_queue.pop(timeout: 60)
        break if v == :stop

        begin
          next if get_daemon_status[:status] != 'ok'
        rescue StandardError => e
          log "Watchdog: Failed to check daemon status: #{e.message} (#{e.class})"
          next
        end

        @watchdog_watcher_queue << :alive
      end
    end

    def get_daemon_status
      sock = UNIXSocket.new(NodeCtld::RemoteControl::SOCKET)
      _greetings = remote_receive(sock)

      sock.puts({ command: :status, params: {} }.to_json)

      remote_receive(sock)
    end

    def remote_receive(sock)
      buf = ''

      while (m = sock.recv(1024))
        buf += m
        break if m[-1].chr == "\n"
      end

      JSON.parse(buf, symbolize_names: true)
    end
  end
end
