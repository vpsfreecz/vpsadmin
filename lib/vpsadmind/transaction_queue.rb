module VpsAdmind
  class TransactionQueue
    def initialize(name, start_time)
      @name = name
      @start_time = start_time
      @workers = {}
    end

    def execute(cmd)
      if !free_slot?(cmd) || !started?
        return false
      end

      @workers[cmd.chain_id] = Worker.new(cmd)
    end

    def empty?
      @workers.empty?
    end

    def full?
      s = $CFG.get(:vpsadmin, :queues, @name)
      used >= s[:threads] + s[:urgent]
    end

    def free_slot?(cmd)
      used < size || (cmd.urgent? && size < total_size)
    end

    def busy?(chain_id)
      @workers.has_key?(chain_id)
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
      @workers.delete_if(&block)
    end

    protected
    def cfg(*args)
      $CFG.get(* [:vpsadmin, :queues, @name].concat(args))
    end
  end
end
