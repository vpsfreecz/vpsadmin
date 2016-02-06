module VpsAdmind
  class Queues
    def initialize(daemon)
      @daemon = daemon
      @queues = {}
      
      %w(general storage network vps zfs_send mail outage).each do |q|
        @queues[q.to_sym] = TransactionQueue.new(q.to_sym, @daemon.start_time)
      end
    end

    def [](name)
      @queues[name]
    end

    def each(&block)
      @queues.each(&block)
    end
    
    def each_value(&block)
      @queues.each_value(&block)
    end

    def execute(cmd)
      return false if busy?(cmd.chain_id)
      @queues[ cmd.queue ].execute(cmd)
    end

    def empty?
      @queues.each_value do |q|
        return false unless q.empty?
      end

      true
    end

    def full?
      @queues.each_value do |q|
        return false unless q.full?
      end

      true
    end

    def free_slot?(cmd)
      @queues[ cmd.queue ].free_slot?(cmd)
    end

    def busy?(chain_id)
      @queues.each_value do |q|
        return true if q.busy?(chain_id)
      end

      false
    end

    def has_transaction?(t_id)
      @queues.each_value do |q|
        return true if q.has_transaction?(t_id)
      end

      false
    end

    def worker_count
      @queues.inject(0) { |sum, q| sum + q[1].used }
    end

    def total_limit
      @queues.values.inject(0) { |sum, q| sum + q.total_size }
    end
  end
end
