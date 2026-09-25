# frozen_string_literal: true

require 'securerandom'
require 'nodectld/storage_effect_registry'

module NodeCtld
  # Local observation only. Child coverage is deliberately incomplete, so this
  # provider never asserts that the node is quiet or ready for a repair.
  class NodeActivity
    VERSION = 1
    COVERAGE = 'node_activity_v1'
    COUNT_CAP = 1000
    REASON_CAP = 16
    DEFAULT_TIMEOUT = 0.05
    CHILD_COVERAGE = 'unknown'

    attr_reader :daemon_boot_uuid

    def initialize
      @daemon_boot_uuid = SecureRandom.uuid
      @mutex = Mutex.new
      @effect_generation = 0
      @sample_generation = 0
      @workers = {}
      @children = {}
      @pending_reservations = 0
      @unknown_reasons = []
    end

    def effectful?(cmd)
      entry = StorageEffectRegistry.fetch!(Integer(cmd.type))
      impact = case cmd.current_chain_direction
               when :execute then entry.execute_impact
               when :rollback then entry.rollback_impact
               else return true
               end
      impact != :none
    rescue StandardError
      true
    end

    # Queue-control commands can reserve slots for a mutating chain even when
    # their own handler is no-storage. Only a classified read-only transaction
    # may make a reservation without advancing the effect generation.
    def reservation_effectful?(cmd)
      entry = StorageEffectRegistry.fetch!(Integer(cmd.type))
      !(entry.execute == :read_only && entry.rollback == :no_storage &&
        entry.execute_impact == :none && entry.rollback_impact == :none)
    rescue StandardError
      true
    end

    def worker_begin(queue, cmd)
      effectful = effectful?(cmd)
      token = Object.new
      @mutex.synchronize do
        tick(effectful:)
        @workers[token] = { queue:, effectful:, registered: false }
      end
      token
    end

    def worker_registered(token)
      @mutex.synchronize do
        worker = @workers[token]
        worker ? worker[:registered] = true : add_reason('worker_record_missing')
        tick
      end
    end

    def worker_saved(token)
      @mutex.synchronize do
        worker = @workers.delete(token)
        worker ? tick(effectful: worker[:effectful]) : add_reason('worker_record_missing')
      end
    end

    def worker_lost(token, reason = 'worker_removed_without_save')
      @mutex.synchronize do
        worker = @workers.delete(token)
        add_reason(reason)
        tick(effectful: worker ? worker[:effectful] : true)
      end
    end

    def worker_killed(token)
      @mutex.synchronize do
        add_reason('worker_killed_child_unproved')
        worker = @workers[token]
        tick(effectful: worker ? worker[:effectful] : true)
      end
    end

    def reservation_begin(effectful: true)
      @mutex.synchronize do
        @pending_reservations += 1
        tick(effectful:)
      end
    end

    def reservation_end(effectful: true)
      @mutex.synchronize do
        @pending_reservations -= 1
        add_reason('reservation_counter_invalid') if @pending_reservations < 0
        tick(effectful:)
      end
    end

    def uncertain!(reason, effectful: true)
      @mutex.synchronize do
        add_reason(reason)
        tick(effectful:)
      end
    end

    def child_begin
      token = Object.new
      @mutex.synchronize do
        @children[token] = true
        tick(effectful: true)
      end
      token
    end

    def child_finished(token)
      @mutex.synchronize do
        add_reason('child_record_missing') unless @children.delete(token)
        tick(effectful: true)
      end
    end

    def child_lost(token)
      @mutex.synchronize do
        add_reason('child_wait_unproved')
        @children.delete(token)
        tick(effectful: true)
      end
    end

    def snapshot(queues:, blockers:, timeout: DEFAULT_TIMEOUT)
      deadline = monotonic + timeout
      before = state(deadline)
      queue_counts = queues.activity_counts(deadline:) if before
      blocker_count = blockers.call(deadline:) if before
      after = state(deadline)
      reasons = ['child_lifetime_unproved']
      reasons.concat(after ? after[:unknown_reasons] : ['tracker_lock_timeout'])
      reasons << 'queue_snapshot_unavailable' if queue_counts.nil?
      reasons << 'blocker_snapshot_unavailable' if blocker_count.nil?

      if before && after
        reasons << 'sample_changed' if before[:sample_generation] != after[:sample_generation]
        reasons << 'worker_start_in_progress' if after[:workers].any? { |w| !w[:registered] }
        reasons << 'reservation_in_progress' if after[:pending_reservations] != 0
        if queue_counts && queue_counts.values.sum { |v| v[:workers] } != after[:workers].size
          reasons << 'worker_count_mismatch'
        end
        reasons << 'child_count_mismatch' if blocker_count && blocker_count != after[:children]
      end

      counts = queue_counts&.values&.flat_map(&:values)
      counts = (counts || []) + [blocker_count, after&.dig(:children), after&.dig(:pending_reservations)]
      overflow = counts.compact.any? { |count| !count.is_a?(Integer) || count < 0 || count > COUNT_CAP }
      reasons << 'count_overflow' if overflow
      reasons = reasons.uniq
      if reasons.length > REASON_CAP
        reasons = reasons.first(REASON_CAP - 1) + ['reason_overflow']
        overflow = true
      end

      {
        version: VERSION, coverage: COVERAGE, daemon_boot_uuid: daemon_boot_uuid,
        effect_generation: after&.dig(:effect_generation),
        sample_monotonic_ns: Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond),
        queues: queue_counts && queue_counts.transform_values do |v|
          v.transform_values { |count| bounded(count) }
        end,
        pending_reservations: bounded(after&.dig(:pending_reservations)),
        detached_blockers: bounded(blocker_count),
        tracked_children: bounded(after&.dig(:children)),
        child_coverage: CHILD_COVERAGE,
        unknown_reasons: reasons, unknown: true, overflow:
      }
    end

    def self.with_mutex(mutex, deadline:)
      until mutex.try_lock
        return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

        sleep 0.001
      end
      begin
        yield
      ensure
        mutex.unlock
      end
    end

    private

    def state(deadline)
      self.class.with_mutex(@mutex, deadline:) do
        {
          effect_generation: @effect_generation,
          sample_generation: @sample_generation,
          workers: @workers.values.map(&:dup),
          children: @children.size,
          pending_reservations: @pending_reservations,
          unknown_reasons: @unknown_reasons.dup
        }
      end
    end

    def tick(effectful: false)
      @sample_generation += 1
      @effect_generation += 1 if effectful
    end

    def add_reason(reason)
      @unknown_reasons << reason unless @unknown_reasons.include?(reason)
      return if @unknown_reasons.length <= REASON_CAP

      @unknown_reasons = @unknown_reasons.first(REASON_CAP - 1) + ['reason_overflow']
    end

    def bounded(count)
      return nil unless count.is_a?(Integer) && count >= 0

      count.clamp(0, COUNT_CAP)
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
