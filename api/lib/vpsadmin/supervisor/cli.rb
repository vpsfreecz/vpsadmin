require 'yaml'

module VpsAdmin
  module Supervisor::Cli
    def self.run
      if ARGV.empty?
        run_supervisor
      elsif ARGV.length == 2 && ARGV[0] == 'run-server'
        run_server(ARGV[1].to_i)
      else
        warn "Usage: #{$0} [run-server <n>]"
        exit(false)
      end
    end

    def self.run_supervisor
      cfg = parse_config
      server_count = cfg.fetch('servers', 1)

      if server_count == 1 && (!cfg.has_key?('foreground') || cfg.fetch('foreground', false))
        Supervisor.start(cfg)
        wait_loop
        return
      end

      if cfg.fetch('foreground', true)
        pids = server_count.times.map do |i|
          spawn_server(i)
        end

        pids.each { |pid| Process.wait(pid) }
        return
      end

      pid = Process.fork do
        server_count.times do |i|
          spawn_server(i)
        end
      end

      Process.wait(pid)
    end

    def self.spawn_server(i)
      Process.fork { Process.exec($0, 'run-server', i.to_s) }
    end

    def self.run_server(i)
      Process.setproctitle("vpsadmin-supervisor: ##{i}")

      cfg = parse_config
      Supervisor.start(cfg)
      wait_loop
    end

    def self.parse_config
      YAML.safe_load_file(File.join(VpsAdmin::API.root, 'config/supervisor.yml'))
    end

    def self.wait_loop
      loop do
        sleep(5)
      end
    end
  end
end
