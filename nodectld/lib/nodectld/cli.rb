require 'optparse'
require 'libosctl'
require 'nodectld/config'
require 'nodectld/daemon'

module NodeCtld
  module Cli
    include OsCtl::Lib::Utils::Log

    def self.run
      options = {
        config: '/etc/vpsadmin/nodectld.yml',
        check: false,
        export_console: false,
        logger: :stdout,
        wrapper: true,
      }

      OptionParser.new do |opts|
        opts.on('-c', '--config [CONFIG FILE]', 'Config file') do |cfg|
          options[:config] = cfg
        end

        opts.on('-e', '--export-console', 'Export VPS consoles via socket') do
          options[:export_console] = true
        end

        opts.on('-k', '--check', 'Check config file syntax') do
          options[:check] = true
        end

        opts.on('-l', '--log LOGGER', %w(syslog stdout)) do |v|
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

        r, w = IO.pipe

        loop do
          pid = Process.fork do
            STDOUT.reopen(w)
            STDERR.reopen(w)
            r.close

            run_daemon(options)
          end

          w.close

          Signal.trap('CHLD') do
            r.close
          end

          Signal.trap('TERM') do
            log 'Killing daemon'
            Process.kill('TERM', pid)
            exit
          end

          Signal.trap('HUP') do
            Process.kill('HUP', p.pid)
          end

          begin
            r.each do |line|
              log(:unknown, line)
            end
          rescue IOError
          end

          # Sets $?
          Process.waitpid(pid)

          case $?.exitstatus
          when NodeCtld::EXIT_OK
            log 'Stopping daemon'
            exit

          when NodeCtld::EXIT_STOP
            log 'Stopping daemon'
            exit

          when NodeCtld::EXIT_RESTART
            log 'Restarting daemon'
            next

          else
            log "Daemon crashed with exit status #{$?.exitstatus}"
            exit(false)
          end
        end
      end

      run_daemon(options)
    end

    def self.run_daemon(options)
      $CFG.load_db_settings

      log(:info, :init, 'nodectld starting')

      Thread.abort_on_exception = true
      nodectld = NodeCtld::Daemon.new
      nodectld.start_em(options[:export_console])
      nodectld.init
      nodectld.start
    end
  end
end
