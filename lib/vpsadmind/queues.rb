module VpsAdmind
  class Queues
    def initialize(daemon)
      @daemon = daemon
      @queues = {}
      
      %w(general storage network vps zfs_send mail outage).each do |q|
        @queues[q.to_sym] = {}
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
      if busy?(cmd.chain_id) || !free_slot?(cmd) || !started?(cmd.queue)
        return false
      end

      @queues[cmd.queue][cmd.chain_id] = Worker.new(cmd)
    end

    def empty?
      @queues.each_value do |q|
        return false unless q.empty?
      end

      true
    end

    def full?
      $CFG.get(:vpsadmin, :queues) do |queues|
        queues.each do |name, q|
          return false if @queues[name].size < (q[:threads] + q[:urgent])
        end
      end

      true
    end

    def free_slot?(cmd)
      $CFG.get(:vpsadmin, :queues, cmd.queue) do |q|
        size = @queues[cmd.queue].size
        return size < q[:threads] || (cmd.urgent? && size < (q[:threads] + q[:urgent]))
      end
    end

    def busy?(chain)
      @queues.each_value do |q|
        return true if q.has_key?(chain)
      end

      false
    end

    def started?(queue)
      d = $CFG.get(:vpsadmin, :queues, queue, :start_delay)
      (@daemon.start_time + d) < Time.now
    end

    def has_transaction?(t_id)
      @queues.each_value do |q|
        q.each do |wid, w|
          return true if w.cmd.id.to_i == t_id
        end
      end

      false
    end

    def worker_count
      @queues.inject(0) { |sum, q| sum + q[1].size }
    end

    def total_limit
      sum = 0

      $CFG.get(:vpsadmin, :queues) do |queues|
        queues.each_value do |q|
          sum += q[:threads] + q[:urgent]
        end
      end

      sum
    end
  end
end
