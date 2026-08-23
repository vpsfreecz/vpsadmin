module NodeCtld
  class TransactionWatchdog
    WARN_AFTER = 600
    DEBUG_AFTER = 810
    RESTART_AFTER = 900
    WARNING_INTERVAL = 90

    Result = Struct.new(
      :stale_for,
      :warn,
      :debug,
      :restart,
      :recovered_from
    )

    def initialize(started_at:)
      @last_check = started_at
      @last_warning = nil
      @debugged = false
      @last_stale_for = nil
    end

    def observe(now:, last_check: nil)
      @last_check = last_check unless last_check.nil?
      stale_for = [now - @last_check, 0].max

      if stale_for < WARN_AFTER
        recovered_from = @last_stale_for
        @last_warning = nil
        @debugged = false
        @last_stale_for = nil

        return Result.new(stale_for:, recovered_from:)
      end

      warn = @last_warning.nil? || stale_for - @last_warning >= WARNING_INTERVAL
      debug = stale_for >= DEBUG_AFTER && !@debugged

      @last_warning = stale_for if warn
      @debugged = true if debug
      @last_stale_for = stale_for

      Result.new(
        stale_for:,
        warn:,
        debug:,
        restart: stale_for >= RESTART_AFTER
      )
    end
  end
end
