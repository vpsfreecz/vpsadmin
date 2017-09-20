module VpsAdmind
  class Queues
    QUEUES = [
        :general,
        :storage,
        :network,
        :vps,
        :zfs_send,
        :mail,
        :outage,
        :queue,
        :rollback,
    ]

    def initialize(daemon)
      @daemon = daemon
      @queues = {}
      
      QUEUES.each do |q|
        @queues[q] = TransactionQueue.new(q, @daemon.start_time)
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
      @queues[ queue_for(cmd) ].execute(cmd)
    end

    def reserve(queues, cmd)
      queues = [queues] unless queues.is_a?(::Array)

      queues.each do |q|
        @queues[q].reserve(cmd)
      end
    end

    def prune_reservations(db)
      chain_reservations = {}

      @queues.each do |name, q|
        q.reservations.each do |chain_id|
          chain_reservations[chain_id] ||= []
          chain_reservations[chain_id] << name
        end
      end

      return 0 if chain_reservations.empty?

      counter = 0

      db.query(
          "SELECT id
          FROM transaction_chains
          WHERE id IN (#{chain_reservations.keys.join(',')}) AND (state = 2 OR state >= 4)"
      ).each_hash do |row|
        chain_id = row['id'].to_i

        chain_reservations[chain_id].each do |q_name|
          if @queues[q_name].release(chain_id)
            counter += 1
          end
        end
      end

      counter
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

    protected
    def queue_for(cmd)
      if cmd.current_chain_direction == :rollback
        :rollback

      else
        cmd.queue
      end
    end
  end
end
