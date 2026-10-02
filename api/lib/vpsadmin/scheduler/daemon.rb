module VpsAdmin
  class Scheduler::Daemon
    DEFAULT_TASK_REFRESH_INTERVAL = 10_800

    attr_reader :task_refresh_interval

    def self.run
      scheduler = new
      scheduler.run
    end

    def initialize(task_refresh_interval: ENV.fetch('SCHEDULER_TASK_REFRESH_INTERVAL', DEFAULT_TASK_REFRESH_INTERVAL))
      @task_refresh_interval = Integer(task_refresh_interval.to_s, 10)
      raise ArgumentError, 'task refresh interval must be positive' unless @task_refresh_interval > 0

      @queue = Queue.new
      @worker = Scheduler::Worker.new
      @scheduler = Scheduler::CronScheduler.new(@worker)
      @server = Scheduler::Server.new(self, @scheduler, @worker)
    end

    def run
      @worker.start
      @scheduler.start
      @server.start

      loop do
        puts 'Updating tasks'
        replace_tasks
        puts "#{@scheduler.size} tasks registered"
        @queue.pop(timeout: @task_refresh_interval)
      end
    end

    def update
      @queue << :update
    end

    protected

    def replace_tasks
      ActiveRecord::Base.connection_pool.with_connection do
        @scheduler.replace do
          RepeatableTask.all.order(:id).each do |t|
            @scheduler.add_task(
              id: t.id,
              class_name: t.class_name,
              row_id: t.row_id,
              minute: t.minute,
              hour: t.hour,
              day: t.day_of_month,
              month: t.month,
              weekday: t.day_of_week
            )
          rescue Scheduler::CronTask::InvalidField => e
            puts "Rejected repeatable task #{t.id}: #{e.message}"
            raise
          end
        end
      end
    rescue Scheduler::CronTask::InvalidField
      false
    end
  end
end
