require 'libosctl'
require 'monitor'

module NodeCtld
  class TransactionQueue
    # A priority-based semaphore
    #
    # Higher priority downs take precedence over lower priority ones
    class Semaphore
      Item = Struct.new(:priority, :order, :queue)

      def initialize(size)
        @size = size
        @comm_queue = ::Queue.new
        @mutex = ::Mutex.new
        @used = 0
        @waiting_items = []
        @counter = 0
      end

      def start
        Thread.new do
          loop do
            c, *args = comm_queue.pop

            case c
            when :down
              prio, queue = args
              sem_down(prio, queue)
            when :up
              sem_up
            when :resize
              sem_resize(args[0])
            end
          end
        end
      end

      def down_block(priority: 0)
        q = ::Queue.new
        comm_queue << [:down, priority, q]
        q.pop
      end

      def down_now
        mutex.synchronize do
          raise ThreadError, 'programming error, no free slot' unless used < size

          @used += 1
          true
        end
      end

      def up
        comm_queue << [:up]
        nil
      end

      def resize(new_size)
        comm_queue << [:resize, new_size]
      end

      protected

      attr_reader :size, :comm_queue, :mutex, :used, :waiting_items, :counter

      def sem_down(priority, queue)
        mutex.synchronize do
          if used < size
            @used += 1
            queue << true
          else
            item = Item.new(priority, counter, queue)
            @counter += 1
            waiting_items << item
          end
        end
      end

      def sem_up
        mutex.synchronize do
          if waiting_items.any? && used <= size
            sort_queue!
            item = waiting_items.shift
            item.queue << true
          elsif waiting_items.any?
            @used -= 1 if used > 0
          else
            @used -= 1 if used > 0
            @counter = 0
          end
        end
      end

      def sem_resize(new_size)
        mutex.synchronize do
          old_size = @size
          @size = new_size

          if new_size > old_size && waiting_items.any?
            sort_queue!

            while waiting_items.any? && used < size
              item = waiting_items.shift
              item.queue << true
              @used += 1
            end
          end
        end
      end

      # Sort first by priority, then order of addition
      def sort_queue!
        waiting_items.sort! do |a, b|
          if b.priority == a.priority
            a.order <=> b.order
          else
            b.priority <=> a.priority
          end
        end
      end
    end

    include OsCtl::Lib::Utils::Log

    def initialize(name, start_time, activity: nil)
      @name = name
      @start_time = start_time
      @workers = {}
      @activity = activity

      @open = true

      @size = cfg(:threads)
      @urgent_size = cfg(:urgent)
      @start_delay = cfg(:start_delay)

      @mon = Monitor.new
      @sem = Semaphore.new(@size)
      @sem.start

      @reserved = []
      @reservation_effects = []

      $CFG.on_update("queue_#{name}") { update_config }
    end

    def execute(cmd)
      return false if !open? || !free_slot?(cmd) || !started?

      if !has_reservation?(cmd.chain_id) && !cmd.urgent?
        begin
          @sem.down_now
        rescue ThreadError
          log(:info, :queue, 'Prevented deadlock')
          return false
        end
      end

      token = @activity&.worker_begin(@name, cmd)
      registered = false
      begin
        worker = if @activity
                   Worker.new(cmd, activity: @activity, activity_token: token)
                 else
                   Worker.new(cmd)
                 end
        @mon.synchronize { @workers[cmd.chain_id] = worker }
        @activity&.worker_registered(token)
        registered = true
        worker
      ensure
        @activity&.worker_lost(token, 'worker_start_unproved') if token && !registered
      end
    end

    def reserve(chain_id, priority: 0, command: nil)
      effectful = @activity ? @activity.reservation_effectful?(command) : true
      @activity&.reservation_begin(effectful:)
      completed = false
      begin
        @sem.down_block(priority:)
        @mon.synchronize do
          @reserved << chain_id
          @reservation_effects << effectful
        end
        completed = true
        true
      ensure
        @activity&.uncertain!('reservation_failed', effectful:) unless completed
        @activity&.reservation_end(effectful:)
      end
    end

    def release(chain_id)
      @mon.synchronize do
        index = @reserved.index(chain_id)
        return false unless index

        effectful = @reservation_effects.fetch(index)
        @activity&.reservation_begin(effectful:)
        begin
          @reserved.delete_at(index)
          @reservation_effects.delete_at(index)
          @sem.up
          true
        ensure
          @activity&.reservation_end(effectful:)
        end
      end
    end

    def pause(seconds = nil)
      @open = false
      @start_delay =
        if seconds
          (Time.now - @start_time).round + seconds
        else
          0
        end
    end

    def resume
      @open = true
      @start_delay = 0
    end

    def open?
      @open || (@start_delay > 0 && started?)
    end

    def empty?
      @mon.synchronize { @workers.empty? }
    end

    def full?
      s = $CFG.get(:vpsadmin, :queues, @name)
      used >= s[:threads] + s[:urgent]
    end

    def free_slot?(cmd)
      return true if has_reservation?(cmd.chain_id)

      s = real_size
      used < s || (cmd.urgent? && used < total_size)
    end

    def busy?(chain_id)
      @mon.synchronize { @workers.has_key?(chain_id) }
    end

    def has_reservation?(chain_id)
      @mon.synchronize { @reserved.include?(chain_id) }
    end

    def reservations
      @mon.synchronize { @reserved.clone }
    end

    def started?
      (@start_time + start_delay) < Time.now
    end

    def has_transaction?(t_id)
      @mon.synchronize do
        @workers.each_value do |w|
          return true if w.cmd.id.to_i == t_id
        end
      end

      false
    end

    def used
      @mon.synchronize { @workers.size }
    end

    attr_reader :size, :urgent_size, :start_delay

    def reserved_size
      @mon.synchronize { @reserved.size }
    end

    def real_size
      size - reserved_size
    end

    def total_size
      size + urgent_size
    end

    def each(&)
      @workers.each(&)
    end

    def each_value(&)
      @workers.each_value(&)
    end

    def delete_if(saved: false, &block)
      @mon.synchronize { @workers.to_a }.each do |wid, w|
        next unless block.call(wid, w)

        @mon.synchronize do
          next unless @workers[wid].equal?(w)

          if @activity
            if saved
              @activity.worker_saved(w.activity_token)
            else
              @activity.worker_lost(w.activity_token)
            end
          end
          @workers.delete(wid)
          @sem.up if !has_reservation?(w.cmd.chain_id) && !w.cmd.urgent?
        end
      end
    end

    def clear!
      @mon.synchronize do
        @workers.each_value do |worker|
          @activity&.worker_lost(worker.activity_token)
        end
        @workers.clear
      end
    end

    def activity_counts(deadline:, excluding_transaction_id: nil)
      until @mon.try_enter
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.001
      end
      begin
        if excluding_transaction_id
          excluded = @workers.values.count do |worker|
            worker.cmd.id.to_i == excluding_transaction_id.to_i
          end
          { workers: @workers.size - excluded, reservations: @reserved.size,
            excluded: }
        else
          { workers: @workers.size, reservations: @reserved.size }
        end
      ensure
        @mon.exit
      end
    end

    def log_type
      "queue:#{@name}"
    end

    protected

    def update_config
      old_size = @size
      new_size = cfg(:threads)

      if new_size != old_size
        log(:info, "Resize #{old_size} -> #{new_size} slots")
        @sem.resize(new_size)
      end

      @size = new_size
      @urgent_size = cfg(:urgent)
      @start_delay = cfg(:start_delay)
    end

    def cfg(*args)
      $CFG.get(* [:vpsadmin, :queues, @name].concat(args))
    end
  end
end
