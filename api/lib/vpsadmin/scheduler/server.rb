require 'fileutils'

module VpsAdmin
  class Scheduler::Server
    SOCKET = ENV.fetch('SCHEDULER_SOCKET', '/run/vpsadmin-scheduler.sock')

    attr_reader :daemon, :scheduler, :worker

    # @param daemon [Scheduler::Daemon]
    # @param scheduler [Scheduler::CronScheduler]
    # @param worker [Scheduler::Worker]
    def initialize(daemon, scheduler, worker)
      @daemon = daemon
      @scheduler = scheduler
      @worker = worker
    end

    def start
      FileUtils.rm_f(SOCKET)
      @srv = UNIXServer.new(SOCKET)

      puts "Server listening on #{SOCKET}"

      @thread = Thread.new { run }
    end

    protected

    def run
      loop do
        handle_client(@srv.accept)
      end
    end

    def handle_client(sock)
      c = Client.new(sock, self)
      c.communicate
    end

    class Client
      def initialize(sock, server)
        @sock = sock
        @server = server
      end

      def communicate
        parse(@sock.readline)
        @sock.close
      rescue Errno::ECONNRESET
        # pass
      end

      def parse(data)
        begin
          json = JSON.parse(data)
        rescue TypeError, JSON::ParserError
          return send_error('Syntax error')
        end

        run(json)
      end

      def run(json)
        begin
          cmd = json.fetch('command')
          args = json.fetch('arguments')
        rescue KeyError
          return send_error('Invalid request')
        end

        case cmd
        when 'status'
          send_ok({ task_count: @server.scheduler.size })

        when 'get-tasks'
          send_ok({ tasks: @server.scheduler.get_tasks.each_value.map(&:export) })

        when 'run-task'
          task_id = args[0].to_i

          cron_task = @server.scheduler.get_task(task_id)
          return send_error("Task #{task_id.inspect} not found") if cron_task.nil?

          @server.worker << cron_task
          send_ok('Task executed')

        when 'update'
          @server.daemon.update
          send_ok('Done')

        else
          send_error("Command #{cmd.inspect} not known")
        end
      end

      def send_error(err)
        send_data({ status: false, error: err })
      end

      def send_ok(res)
        send_data({ status: true, response: res })
      end

      def send_data(data)
        @sock.puts(data.to_json)
      rescue Errno::EPIPE
        # ignore
      end
    end
  end
end
