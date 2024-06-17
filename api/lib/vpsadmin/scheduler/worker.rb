module VpsAdmin
  class Scheduler::Worker
    def initialize
      @queue = Queue.new
    end

    def start
      @thread = Thread.new do
        loop do
          cron_task = @queue.pop
          run_task(cron_task)
        end
      end
    end

    # @param cron_task [Scheduler::CronTask]
    def <<(cron_task)
      @queue << cron_task
    end

    protected

    def run_task(cron_task)
      ActiveRecord::Base.connection_pool.with_connection do
        klass = Object.const_get(cron_task.class_name)
        task = klass.find_by(klass.primary_key => cron_task.row_id)

        unless task
          warn "Action #{cron_task.class_name} = #{cron_task.row_id} not found"
          next
        end

        begin
          puts "Executing task #{task.id}"
          task.execute
        rescue StandardError => e
          warn "Repeatable task ##{task.id} failed!"
          warn e.inspect
          warn e.backtrace
        end
      end
    end
  end
end
