require 'optparse'
require 'libosctl'
require 'nodectld/config'
require 'nodectld/daemon'

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
        wrapper: true
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
        run_wrapper
        return
      end

      run_daemon
    end

    protected

    def run_wrapper
      @stop = false
      @stop_queue = OsCtl::Lib::Queue.new

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

        begin
          r.each do |line|
            log(:unknown, line)
          end
        rescue IOError
          r = nil
        end

        Process.waitpid(pid)
        @stop_queue << pid

        if @stop
          @stop_thread.join
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
  end
end
