module NodeCtld
  class TransactionQueue
    class Semaphore
      def initialize(size)
        @q = ::Queue.new
        size.times { @q << nil }
      end

      def up
        @q << nil
      end

      def down(non_block = false)
        @q.pop(non_block)
      end
    end

    include OsCtl::Lib::Utils::Log

    def initialize(name, start_time)
      @name = name
      @start_time = start_time
      @workers = {}
      @mon = Monitor.new
      @sem = Semaphore.new(size)
      @reserved = []
    end

    def execute(cmd)
      if !free_slot?(cmd) || !started?
        return false
      end

      unless has_reservation?(cmd.chain_id)
        begin
          @sem.down(true)

        rescue ThreadError
          log(:info, :queue, 'Prevented deadlock')
          return false
        end
      end

      @workers[cmd.chain_id] = Worker.new(cmd)
    end

    def reserve(chain_id)
      @sem.down
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

    def empty?
      @workers.empty?
    end

    def full?
      s = $CFG.get(:vpsadmin, :queues, @name)
      used >= s[:threads] + s[:urgent]
    end

    def free_slot?(cmd)
      if has_reservation?(cmd.chain_id)
        s = real_size + 1

      else
        s = real_size
      end

      used < s || (cmd.urgent? && s < total_size)
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
      cfg(:threads)
    end

    def reserved_size
      @mon.synchronize { @reserved.size }
    end

    def real_size
      size - reserved_size
    end

    def urgent_size
      cfg(:urgent)
    end

    def total_size
      size + urgent_size
    end

    def start_delay
      cfg(:start_delay)
    end

    def each(&block)
      @workers.each(&block)
    end

    def delete_if(&block)
      @workers.delete_if do |wid, w|
        ret = block.call(wid, w)
        @sem.up if ret && !has_reservation?(w.cmd.chain_id)
        ret
      end
    end

    def clear!
      @workers.clear
    end

    protected
    def cfg(*args)
      $CFG.get(* [:vpsadmin, :queues, @name].concat(args))
    end
  end
end
