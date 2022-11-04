require 'libosctl'
require 'monitor'
require 'thread'

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
          if used < size
            @used += 1
            true
          else
            raise ThreadError, 'programming error, no free slot'
          end
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
            it = Item.new(priority, counter, queue)
            @counter += 1
            waiting_items << it
          end
        end
      end

      def sem_up
        mutex.synchronize do
          if waiting_items.any? && used <= size
            sort_queue!
            it = waiting_items.shift
            it.queue << true
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
              it = waiting_items.shift
              it.queue << true
              @used += 1
            end
          end
        end
      end

      # Sort first by priority, then order of addition
      def sort_queue!
        waiting_items.sort! do |a, b|
          if b.priority != a.priority
            b.priority <=> a.priority
          else
            a.order <=> b.order
          end
        end
      end
    end

    include OsCtl::Lib::Utils::Log

    def initialize(name, start_time)
      @name = name
      @start_time = start_time
      @workers = {}

      @open = true

      @size = cfg(:threads)
      @urgent_size = cfg(:urgent)
      @start_delay = cfg(:start_delay)

      @mon = Monitor.new
      @sem = Semaphore.new(@size)
      @sem.start

      @reserved = []

      $CFG.on_update("queue_#{name}") { update_config }
    end

    def execute(cmd)
      if !open? || !free_slot?(cmd) || !started?
        return false
      end

      if !has_reservation?(cmd.chain_id) && !cmd.urgent?
        begin
          @sem.down_now

        rescue ThreadError
          log(:info, :queue, 'Prevented deadlock')
          return false
        end
      end

      @workers[cmd.chain_id] = Worker.new(cmd)
    end

    def reserve(chain_id, priority: 0)
      @sem.down_block(priority: priority)
      @mon.synchronize { @reserved << chain_id }
      true
    end

    def release(chain_id)
      @mon.synchronize do
        return false unless @reserved.delete(chain_id)
        @sem.up
        true
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
      @workers.empty?
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
      @workers.has_key?(chain_id)
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
      @workers.each do |wid, w|
        return true if w.cmd.id.to_i == t_id
      end

      false
    end

    def used
      @workers.size
    end

    def size
      @size
    end

    def reserved_size
      @mon.synchronize { @reserved.size }
    end

    def real_size
      size - reserved_size
    end

    def urgent_size
      @urgent_size
    end

    def total_size
      size + urgent_size
    end

    def start_delay
      @start_delay
    end

    def each(&block)
      @workers.each(&block)
    end

    def delete_if(&block)
      @workers.delete_if do |wid, w|
        ret = block.call(wid, w)
        @sem.up if ret && !has_reservation?(w.cmd.chain_id) && !w.cmd.urgent?
        ret
      end
    end

    def clear!
      @workers.clear
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
