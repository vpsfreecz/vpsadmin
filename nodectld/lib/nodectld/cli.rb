require 'optparse'
require 'libosctl'
require 'nodectld/config'
require 'nodectld/daemon'
require 'nodectld/remote_control'
require 'nodectld/transaction_watchdog'
require 'io/wait'
require 'timeout'

module NodeCtld
  class Cli
    include OsCtl::Lib::Utils::Log

    WATCHDOG_CHECK_INTERVAL = 30
    WATCHDOG_RPC_TIMEOUT = 10

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
      @watchdog_queue = OsCtl::Lib::Queue.new

      loop do
        r, w = IO.pipe

        pid = Process.fork do
          reset_child_signal_handlers
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
          daemon_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @watchdog_thread = Thread.new { run_watchdog(pid, daemon_started_at:) }
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
          @watchdog_queue << :stop
          @watchdog_thread.join
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

    def run_watchdog(pid, daemon_started_at:)
      state = TransactionWatchdog.new(started_at: daemon_started_at)

      loop do
        v = @watchdog_queue.pop(timeout: WATCHDOG_CHECK_INTERVAL)
        break if v == :stop

        last_check = nil

        begin
          response = get_daemon_response(:watchdog_status)
          if response[:status] == 'ok'
            last_check = response[:response][:last_transaction_check_monotonic]
          end
        rescue StandardError => e
          log "Watchdog: Failed to check daemon status: #{e.message} (#{e.class})"
        end

        result = state.observe(now: monotonic_now, last_check:)

        if result.recovered_from
          log "Watchdog: transaction polling recovered after #{result.recovered_from.to_i} seconds"
        end

        if result.warn
          log 'Watchdog: transaction polling is stale for ' \
              "#{result.stale_for.to_i}/#{TransactionWatchdog::RESTART_AFTER} seconds"
        end

        log_watchdog_debug(result.stale_for) if result.debug && !result.restart

        next unless result.restart

        log 'Watchdog: transaction polling did not recover in time, restarting'
        @stop = true
        stop_daemon(pid)
        break
      end
    end

    def get_daemon_response(command)
      sock = nil
      deadline = monotonic_now + WATCHDOG_RPC_TIMEOUT

      Timeout.timeout(
        WATCHDOG_RPC_TIMEOUT,
        Timeout::Error,
        'nodectld remote control timed out'
      ) do
        sock = UNIXSocket.new(NodeCtld::RemoteControl::SOCKET)
        _greetings = remote_receive(sock, deadline:)

        sock.puts({ command:, params: {} }.to_json)

        remote_receive(sock, deadline:)
      end
    ensure
      sock&.close
    end

    def remote_receive(sock, deadline:)
      buf = ''

      loop do
        remaining = deadline - monotonic_now
        raise Timeout::Error, 'nodectld remote control timed out' if remaining <= 0

        readable = sock.wait_readable(remaining)
        raise Timeout::Error, 'nodectld remote control timed out' if readable.nil?

        m = sock.recv(1024)
        raise EOFError, 'nodectld remote control closed the connection' if m.empty?

        buf += m
        break if m.end_with?("\n")
      end

      JSON.parse(buf, symbolize_names: true)
    end

    def log_watchdog_debug(stale_for)
      log "Watchdog: transaction polling is stale for #{stale_for.to_i} seconds, " \
          'collecting transaction-loop backtrace'
      response = get_daemon_response(:watchdog_debug)

      unless response[:status] == 'ok'
        log "Watchdog: Failed to collect transaction-loop backtrace: #{response.inspect}"
        return
      end

      thread = response[:response][:transaction_thread]
      log "Watchdog: transaction-loop thread status: #{thread[:status].inspect}"
      thread[:backtrace].each { |line| log "Watchdog: transaction-loop backtrace: #{line}" }
    rescue StandardError => e
      log "Watchdog: Failed to collect transaction-loop backtrace: #{e.message} (#{e.class})"
    end

    def reset_child_signal_handlers
      %w[CHLD TERM INT HUP].each { |signal| Signal.trap(signal, 'DEFAULT') }
    end

    def monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
