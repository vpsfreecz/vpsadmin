# frozen_string_literal: true

module NodeCtldSpec
  FakeWorker = Struct.new(:cmd)

  FakeCmd = Struct.new(
    :id,
    :chain_id,
    :queue,
    :urgent,
    :priority,
    :current_chain_direction,
    :handler,
    :progress,
    :time_start,
    :step,
    :subtask,
    :trans
  ) do
    def urgent?
      !!urgent
    end

    def execute; end
  end

  class FakeDaemon
    attr_reader :queues, :console, :last_transaction_check, :start_time, :exitstatus

    def initialized?; end
    def run?; end
    def paused?; end
    def chain_blockers; end
    def pause(_value = true); end
    def resume; end
    def update_all; end
    def select_commands(_db, _limit); end
  end

  class FakeQueue
    attr_reader :workers, :reservations, :start_delay, :paused_for, :resumed, :reserved, :released

    def initialize(threads: 2, urgent: 1, open: true, started: true, start_delay: 0, reservations: [], workers: {})
      @threads = threads
      @urgent = urgent
      @open = open
      @started = started
      @start_delay = start_delay
      @reservations = reservations
      @workers = workers
      @paused_for = []
      @resumed = false
      @reserved = []
      @released = []
    end

    def size = @threads
    def urgent_size = @urgent
    def open? = @open
    def started? = @started
    def used = @workers.size
    def total_size = @threads + @urgent
    def empty? = @workers.empty?
    def full? = false
    def free_slot?(_cmd) = true
    def busy?(chain_id) = @workers.has_key?(chain_id)
    def has_transaction?(t_id) = @workers.each_value.any? { |w| w.cmd.id.to_i == t_id.to_i }
    def each(&) = @workers.each(&)
    def each_value(&) = @workers.each_value(&)

    def pause(duration = nil)
      @paused_for << duration
      @open = false
    end

    def resume
      @resumed = true
      @open = true
    end

    def reserve(chain_id, priority: 0)
      @reserved << [chain_id, priority]
      @reservations << chain_id
      true
    end

    def release(chain_id)
      @released << chain_id
      @reservations.delete(chain_id)
      true
    end

    def execute(cmd)
      @workers[cmd.chain_id] = FakeWorker.new(cmd)
    end
  end
end
