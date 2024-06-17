module VpsAdmin
  class Scheduler::Daemon
    def self.run
      scheduler = new
      scheduler.run
    end

    def initialize
      @queue = Queue.new
      @worker = Scheduler::Worker.new
      @scheduler = Scheduler::CronScheduler.new(@worker)
    end

    def run
      @worker.start
      @scheduler.start

      loop do
        puts 'Regenerating tasks'
        regenerate
        puts "#{@scheduler.size} tasks registered"
        @queue.pop(timeout: 3 * 60 * 60)
      end
    end

    protected

    def regenerate
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
          end
        end
      end
    end
  end
end
