require 'eventmachine'

module VpsAdmin
  # The scheduler takes care of executing repeatable tasks at configured
  # times.
  #
  # Internally, the scheduler generates a crontab. The cron then calls
  # a wrapper script, which communicates using UNIX socket with the scheduler
  # again, telling it what task should be executed.
  #
  # Tasks to be executed are queued and executed one by one.
  #
  # The scheduler depends on thin to start EventMachine event loop.
  class Scheduler
    CRONTAB = '/etc/cron.d/vpsadmin'
    SOCKET = '/var/run/vpsadmin-scheduler.sock'

    # Internal UNIX domain socket server.
    class Server < EventMachine::Connection
      def initialize(scheduler)
        @scheduler = scheduler
      end

      def receive_data(data)
        data.split('\n').each do |id|
          @scheduler.execute(id.to_i)
        end
      end
    end

    class << self
      # Start the scheduler.
      def start
        @scheduler = new unless running?
      end

      # Stop the scheduler.
      def stop
        @scheduler.stop
        @scheduler = nil
      end

      # True if the scheduler is running.
      def running?
        !@scheduler.nil?
      end

      # Regenerate crontab. This is rather time and resource
      # consuming operation.
      def regenerate
        @scheduler.schedule_changed if running?
      end
    end

    # Create the watcher and worker threads, start UNIX socket server.
    # The watcher is used to regeneration of the crontab.
    # The worker executes tasks.
    def initialize
      @actions = {}
      @queue = Queue.new
      @gen_mutex = Mutex.new
      @gen_cond = ConditionVariable.new
      @action_mutex = Mutex.new
      @run = true

      @watcher = Thread.new do
        watcher
      end

      @executor = Thread.new do
        work
      end

      # Event machine loop must be started outside this class
      EventMachine.next_tick do
        @em_server = EventMachine.start_unix_domain_server(SOCKET, Server, self)
      end
    end

    # Stop all threads, stop the socket server, remove crontab.
    # The queue of pending tasks is cleared right away.
    def stop
      @run = false

      EventMachine.stop_server(@em_server)
      File.delete(CRONTAB) if File.exist?(CRONTAB)

      @queue.clear
      @queue << :stop

      @gen_mutex.synchronize do
        @gen_cond.signal
      end

      @watcher.join
      @executor.join
    end

    # Instruct the watcher thread to regenerate the crontab.
    def schedule_changed
      @gen_mutex.synchronize do
        @gen_cond.signal
      end
    end

    # Enqueue action with +id+ for execution.
    def execute(id)
      @queue << id
    end

    private
    # Watcher thread.
    # The watcher exits when signalled and @run is false.
    def watcher
      generate

      catch(:exit) do
        loop do
          @gen_mutex.synchronize do
            @gen_cond.wait(@gen_mutex)

            throw(:exit) unless @run
            generate
          end
        end
      end
    end

    def generate
      ActiveRecord::Base.connection_pool.with_connection do
        crontab = File.open(CRONTAB, 'w')
        crontab.write("# This file is generated by vpsAdmin, all changes will be lost\n\n")

        @action_mutex.synchronize do
          @actions.clear

          RepeatableTask.all.order(:id).each do |t|
            @actions[t.id] = {
              class_name: t.class_name,
              row_id: t.row_id
            }

            crontab.write(
              "#{t.minute} #{t.hour} #{t.day_of_month} #{t.month} #{t.day_of_week} " +
              "root /opt/vpsadmin/api/bin/vpsadmin-run-task #{SOCKET} #{t.id}\n"
            ) # FIXME: remove hardcoded path
          end
        end

        crontab.close
      end
    end

    # Worker thread.
    # The worker stops execution if :stop is popped from the queue.
    def work
      loop do
        id = @queue.pop

        break if id == :stop

        @action_mutex.synchronize do
          ActiveRecord::Base.connection_pool.with_connection do
            act = @actions[id]
            unless act
              warn "Task ##{id} not found"
              next
            end

            cls = Object.const_get(act[:class_name])
            task = cls.find_by(cls.primary_key => act[:row_id])

            unless task
              warn "Action #{act[:class_name]} = #{act[:row_id]} not found"
              next
            end

            begin
              task.execute

            rescue => e
              warn "Repeatable task ##{task.id} failed!"
              warn e.inspect
              warn e.backtrace
            end
          end
        end
      end
    end
  end
end
