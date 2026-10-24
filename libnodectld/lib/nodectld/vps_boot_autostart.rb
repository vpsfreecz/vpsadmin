# frozen_string_literal: true

require 'nodectld/vps_boot_autostart_ledger'
require 'nodectld/vps_autostart_status'
require 'nodectld/rpc_client'
require 'nodectld/utils'

module NodeCtld
  class VpsBootAutostart
    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl

    Snapshot = Struct.new(:state, :reason, :success, :last_success_at,
                          :expected, :unsatisfied, :unsatisfied_counts)
    Publication = Struct.new(:snapshot, :enrolling, :expired_snapshot)

    class Failure < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super
      end
    end

    def initialize(ledger_factory: -> { VpsBootAutostartLedger.new }, rpc: RpcClient,
                   clock: -> { Process.clock_gettime(Process::CLOCK_BOOTTIME) })
      @ledger_factory = ledger_factory
      @rpc = rpc
      @ledger = nil
      @initialized = false
      @clock = clock
      @worker_mutex = Mutex.new
      @last_success_at = 0
      @last_capture_failure = nil
      @enrollment_rejection = nil
      @enrolling = false
      @accepted = false
      publish_snapshot(unavailable_snapshot('state_loading'))
    end

    def snapshot
      now = @clock.call
      publication = @publication
      if publication.enrolling && now >= VpsBootAutostartLedger::DEADLINE
        @enrollment_rejection ||= publication.expired_snapshot
      end

      @enrollment_rejection || publication.snapshot
    end

    def update
      locked = @worker_mutex.try_lock
      return unless locked

      initialize_ledger unless @initialized
      return unless @ledger
      return close_enrollment if @enrollment_rejection
      return if @ledger.failure_reason == 'persistence_failed'

      if @enrolling
        enrollment_expired? ? close_enrollment : enroll
      elsif @accepted
        reconcile
      end
      close_enrollment if @enrollment_rejection
    rescue StandardError => e
      log(:warn, :vps_boot_autostart, "Check failed: #{e.class}")
      if @enrollment_rejection || (@enrolling && enrollment_expired?)
        close_enrollment
      else
        if @enrolling
          @last_capture_failure = failure_reason(e) == 'inventory_invalid' ? 'inventory_invalid' : nil
        end
        publish_snapshot(build_snapshot(reason: failure_reason(e)))
      end
    ensure
      @worker_mutex.unlock if locked
    end

    protected

    def initialize_ledger
      @initialized = true
      @ledger = @ledger_factory.call
      @enrolling = @ledger.phase == 'enrolling' && @ledger.failure_reason.nil?
      @accepted = @ledger.phase == 'active' && @ledger.failure_reason.nil?
      publish_snapshot(build_snapshot)
    rescue StandardError => e
      @ledger = nil
      log(:warn, :vps_boot_autostart, "State load failed: #{e.class}")
      publish_snapshot(unavailable_snapshot('state_invalid'))
    end

    def enroll
      return close_enrollment if enrollment_expired?

      # Only the request belongs inside run: its ensure closes the ordinary
      # client before validation or persistence can accept this inventory.
      inventory = @rpc.run(&:list_vps_boot_autostart)
      return close_enrollment if enrollment_expired?

      captured = @ledger.capture(inventory, now: @clock.call, clock: @clock)
      candidate = build_snapshot
      # This check follows validation, writes, rename AND ensure cleanup. A disk
      # candidate alone is not accepted before this publication.
      return close_enrollment if enrollment_expired?

      @enrolling = false
      @accepted = captured && @ledger.phase == 'active' && @ledger.failure_reason.nil?
      @enrollment_rejection ||= candidate unless @accepted
      publish_snapshot(candidate)
      close_enrollment if @enrollment_rejection
    end

    def enrollment_expired?
      !@enrollment_rejection.nil? || @clock.call >= VpsBootAutostartLedger::DEADLINE
    end

    def close_enrollment
      @enrolling = false
      @accepted = false
      reason = @last_capture_failure || 'enrollment_timeout'
      if @enrollment_rejection && VpsBootAutostartLedger::FAILURE_REASONS.include?(@enrollment_rejection.reason)
        reason = @enrollment_rejection.reason
      end
      @enrollment_rejection ||= unavailable_snapshot(reason)
      # Publish first. Timeout persistence belongs solely to this worker and
      # can block without blocking the exporter.
      publish_snapshot(@enrollment_rejection)
      unless @ledger.phase == 'unavailable' && @ledger.failure_reason == reason
        @ledger.enrollment_failed(reason)
      end
      publish_snapshot(build_snapshot)
    end

    def reconcile
      history = fetch_history
      running = validate_history(history)
      ids = @ledger.pending.filter_map do |row|
        row.fetch('id') if running.include?([row.fetch('pool'), row.fetch('id').to_s])
      end
      raise Failure, 'persistence_failed' unless @ledger.transition(fulfilled: ids) && @ledger.failure_reason.nil?

      retired = {}
      @ledger.pending.map { |row| row.fetch('id') }.sort.each_slice(1000) do |pending_ids|
        result = @rpc.run { |rpc| rpc.reconcile_vps_boot_autostart(pending_ids) }
        retired.merge!(validate_reconciliation(pending_ids, result))
      end

      # A diagnostic failure still must not undo proven successes or retirement.
      raise Failure, 'persistence_failed' unless @ledger.transition(retired:) && @ledger.failure_reason.nil?

      containers = diagnostic_containers
      return close_enrollment if @enrollment_rejection

      @last_success_at = Time.now.to_i
      publish_snapshot(build_snapshot(success: true, containers:))
      close_enrollment if @enrollment_rejection
    end

    # MRI publishes a reference atomically. Every referenced object is complete
    # and immutable before assignment. A stale assignment cannot undo terminal
    # rejection: readers and the next worker dispatch always honor it first.
    def publish_snapshot(value)
      @publication = Publication.new(
        snapshot: value, enrolling: @enrolling,
        expired_snapshot: unavailable_snapshot(@last_capture_failure || 'enrollment_timeout')
      ).freeze
    end

    def unavailable_snapshot(reason)
      Snapshot.new(state: 'unavailable', reason: reason.dup.freeze, success: false,
                   last_success_at: @last_success_at, expected: {}.freeze,
                   unsatisfied: [].freeze, unsatisfied_counts: {}.freeze).freeze
    end

    def fetch_history
      JSON.parse(osctl(%i[ct state-history], [], { ever_running: true }).output)
    rescue SystemCommandFailed => e
      raise Failure, e.output.to_s.match?(/unknown command|invalid command|unrecognized/i) ? 'osctld_unsupported' : 'osctld_unavailable'
    end

    def diagnostic_containers
      rows = osctl_parse(%i[ct ls])
      raise Failure, 'response_invalid' unless rows.is_a?(Array)

      ret = {}
      rows.each do |row|
        pool = row[:pool]
        id = row[:id]
        state = row[:state]
        raise Failure, 'response_invalid' unless @ledger.name?(pool) && id.is_a?(String) &&
                                                 !id.empty? && state.is_a?(String) && !state.empty? &&
                                                 !ret.has_key?([pool, id])

        ret[[pool, id]] = state
      end
      ret
    rescue SystemCommandFailed
      raise Failure, 'osctld_unavailable'
    end

    def validate_history(value)
      raise Failure, 'response_invalid' unless value.is_a?(Hash) && value['schema_version'].is_a?(Integer) && value['schema_version'] == 1 &&
                                               value.has_key?('reason') &&
                                               value['boot_id'] == @ledger.record.fetch('boot_id') &&
                                               [true, false].include?(value['available']) && value['entries'].is_a?(Array)

      unless value['available']
        valid = %w[awaiting_reboot state_missing state_invalid boot_id_mismatch persistence_failed].include?(value['reason']) && value['entries'].empty?
        raise Failure, valid ? 'osctld_unavailable' : 'response_invalid'
      end
      raise Failure, 'response_invalid' unless value['reason'].nil?

      keys = value['entries'].map do |row|
        raise Failure, 'response_invalid' unless row.is_a?(Hash) && @ledger.name?(row['pool']) &&
                                                 row['id'].is_a?(String) && /\A[a-z0-9_-]{1,100}\z/i.match?(row['id']) &&
                                                 @ledger.timestamp?(row['first_running_boottime_seconds']) &&
                                                 row['first_running_boottime_seconds'] <= @clock.call

        row.values_at('pool', 'id')
      end
      raise Failure, 'response_invalid' unless keys.uniq.length == keys.length

      keys
    end

    def validate_reconciliation(ids, response)
      raise Failure, 'response_invalid' unless response.is_a?(Hash) && response['schema_version'].is_a?(Integer) &&
                                               response['schema_version'] == 1 && response['vpses'].is_a?(Array)

      rows = response['vpses']
      raise Failure, 'response_invalid' unless rows.all? { |row| row.is_a?(Hash) && @ledger.positive_id?(row['id']) && row.has_key?('pool_fs') } &&
                                               rows.map { |row| row['id'] }.sort == ids

      obligations = @ledger.pending.to_h { |row| [row.fetch('id'), row] }
      retired = {}
      unknown = false
      rows.each do |row|
        id, disposition, reason, pool_fs = row.values_at('id', 'disposition', 'reason', 'pool_fs')
        case disposition
        when 'retire'
          raise Failure, 'response_invalid' unless %w[deleted assigned_elsewhere inactive autostart_disabled].include?(reason) && pool_fs.nil?

          retired[id] = reason
        when 'retain'
          if reason == 'expected'
            raise Failure, 'response_invalid' unless @ledger.pool_fs?(pool_fs)

            retired[id] = 'pool_changed' if @ledger.pool(pool_fs) != obligations.fetch(id).fetch('pool')
          else
            raise Failure, 'response_invalid' unless %w[resource_locked transitional].include?(reason) && pool_fs.nil?
          end
        when 'unknown'
          raise Failure, 'response_invalid' unless reason == 'inventory_invalid' && pool_fs.nil?

          unknown = true
        else
          raise Failure, 'response_invalid'
        end
      end
      raise Failure, 'inventory_invalid' if unknown

      retired
    end

    def failure_reason(error)
      return error.reason if error.is_a?(Failure)
      return 'inventory_invalid' if error.is_a?(VpsBootAutostartLedger::Invalid)
      return 'response_invalid' if error.is_a?(JSON::ParserError)
      return 'rpc_failed' if error.is_a?(RpcClient::Timeout)

      if error.is_a?(RpcClient::Error)
        return 'rpc_unsupported' if /unknown command|unsupported|not allowed|invalid method|Command .* not found/i.match?(error.message)
        return 'inventory_invalid' if /(?:\A|:\s)inventory_invalid\z/.match?(error.message)
      end

      'rpc_failed'
    end

    def build_snapshot(success: false, reason: nil, containers: {})
      phase = @ledger.phase
      ledger_failure = @ledger.failure_reason
      if ledger_failure == 'persistence_failed' || phase == 'unavailable'
        phase = 'unavailable'
        reason = ledger_failure
        success = false
      elsif phase == 'awaiting_reboot'
        reason = 'not_enrolled'
      elsif phase == 'active' && reason
        phase = 'unavailable'
      else
        reason = 'none'
      end

      expected = Hash.new(0)
      unsatisfied = []
      counts = Hash.new(0)
      if success
        @ledger.obligations.each { |row| expected[row.fetch('pool')] += 1 }
        @ledger.pending.each do |row|
          pool = row.fetch('pool').dup.freeze
          vps_id = row.fetch('id').to_s.freeze
          state = containers[[pool, vps_id]]
          diagnostic = if state.nil?
                         'missing'
                       else
                         (state == 'running' ? 'unknown' : 'not_running')
                       end
          unsatisfied << VpsAutostartStatus::Unsatisfied.new(pool:, vps_id:, reason: diagnostic).freeze
          counts[[pool, diagnostic].freeze] += 1
        end
      end
      Snapshot.new(state: phase.dup.freeze, reason: (reason || 'none').dup.freeze, success:, last_success_at: @last_success_at,
                   expected: expected.freeze, unsatisfied: unsatisfied.freeze,
                   unsatisfied_counts: counts.freeze).freeze
    end
  end
end
