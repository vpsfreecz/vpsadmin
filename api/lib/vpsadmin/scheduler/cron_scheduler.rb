module VpsAdmin
  class Scheduler::CronScheduler
    def initialize(worker)
      @cron_tasks = {}
      @mutex = Mutex.new
      @worker = worker
    end

    def add_task(id:, class_name:, row_id:, minute: '*', hour: '*', day: '*', month: '*', weekday: '*')
      cron_task = Scheduler::CronTask.new(
        id:,
        class_name:,
        row_id:,
        minute:,
        hour:,
        day:,
        month:,
        weekday:
      )

      sync do
        @cron_tasks[id] = cron_task
      end
    end

    def get_task(id)
      sync { @cron_tasks[id] }
    end

    def get_tasks
      sync { @cron_tasks.clone }
    end

    def replace
      sync do
        @cron_tasks.clear
        yield
      end
    end

    def start
      @thread = Thread.new { run }
    end

    def size
      @cron_tasks.size
    end

    protected

    def run
      loop do
        current_time = Time.now

        sync do
          @cron_tasks.each do |id, cron_task|
            next unless cron_task.matches?(current_time)

            puts "Scheduling task #{id}"
            @worker << cron_task
          end
        end

        sleep(60 - Time.now.sec) # sleep until the start of the next minute
      end
    end

    def sync(&)
      if @mutex.owned?
        yield
      else
        @mutex.synchronize(&)
      end
    end
  end
end
