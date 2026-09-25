require 'nodectld/transaction_queue'

module NodeCtld
  class Queues
    QUEUES = %i[
      general
      storage
      inventory
      network
      vps
      zfs_send
      zfs_recv
      mail
      dns
      outage
      queue
      rollback
    ].freeze

    def initialize(daemon, activity: nil)
      @daemon = daemon
      @activity = activity
      @mutex = Mutex.new
      @queues = {}

      QUEUES.each do |q|
        @queues[q] = TransactionQueue.new(q, @daemon.start_time, activity:)
      end
    end

    def [](name)
      sync { @queues[name] }
    end

    def each(&)
      sync { @queues.each(&) }
    end

    def each_value(&)
      sync { @queues.each_value(&) }
    end

    def execute(cmd)
      sync do
        return false if busy?(cmd.chain_id)

        @queues[queue_for(cmd)].execute(cmd)
      end
    end

    def reserve(queues, cmd)
      queues = [queues] unless queues.is_a?(::Array)
      chain_id = cmd.chain_id
      priority = cmd.priority || 0

      sync do
        queues.each do |q|
          @queues[q].reserve(chain_id, priority:, command: cmd)
        end
      end
    end

    def prune_reservations(db)
      chain_reservations = {}

      sync do
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
        ).each do |row|
          chain_id = row['id'].to_i

          chain_reservations[chain_id].each do |q_name|
            counter += 1 if @queues[q_name].release(chain_id)
          end
        end

        counter
      end
    end

    def empty?
      sync do
        @queues.each_value do |q|
          return false unless q.empty?
        end

        true
      end
    end

    def full?
      sync do
        @queues.each_value do |q|
          return false unless q.full?
        end

        true
      end
    end

    def free_slot?(cmd)
      sync { @queues[queue_for(cmd)].free_slot?(cmd) }
    end

    def busy?(chain_id)
      sync do
        @queues.each_value do |q|
          return true if q.busy?(chain_id)
        end

        false
      end
    end

    def has_transaction?(t_id)
      sync do
        @queues.each_value do |q|
          return true if q.has_transaction?(t_id)
        end

        false
      end
    end

    def worker_count
      sync do
        @queues.inject(0) { |sum, q| sum + q[1].used }
      end
    end

    def total_limit
      sync do
        @queues.values.inject(0) { |sum, q| sum + q.total_size }
      end
    end

    # A reservation may hold @mutex while waiting on a semaphore. Never wait
    # indefinitely to sample it: nil means the caller must report unknown.
    def activity_counts(deadline:)
      until @mutex.try_lock
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.001
      end
      begin
        return nil unless QUEUES.uniq.length == QUEUES.length &&
                          @queues.keys.sort == QUEUES.sort

        @queues.each_with_object({}) do |(name, queue), counts|
          sample = queue.activity_counts(deadline:)
          return nil unless sample

          counts[name] = sample
        end
      ensure
        @mutex.unlock
      end
    end

    protected

    def queue_for(cmd)
      if cmd.current_chain_direction == :rollback
        :rollback
      elsif cmd.type.to_i == 5290
        :inventory
      else
        cmd.queue
      end
    end

    def sync(&block)
      if @mutex.owned?
        block.call
      else
        @mutex.synchronize(&block)
      end
    end
  end
end
