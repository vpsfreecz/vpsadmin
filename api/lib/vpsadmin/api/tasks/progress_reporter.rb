module VpsAdmin::API::Tasks
  class ProgressReporter
    REPORT_INTERVAL = 5.0

    def initialize(
      label:,
      io: $stdout,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      report_interval: REPORT_INTERVAL
    )
      @label = label
      @io = io
      @clock = clock
      @report_interval = report_interval
    end

    def start(total:, attempt:)
      @total = total
      @processed = 0
      @created = 0
      @started_at = @clock.call
      @last_report_at = @started_at
      @io.puts "#{@label}: started attempt=#{attempt} total=#{total}"
    end

    def advance(processed:, created:)
      @processed = processed
      @created = created
      now = @clock.call
      report('progress', now) if now - @last_report_at >= @report_interval
    end

    def retry(reason:)
      now = @clock.call
      report('retry', now)
      @io.puts "#{@label}: retrying reason=#{reason}"
    end

    def failed(reason:)
      now = @clock.call
      report('failed', now)
      @io.puts "#{@label}: failed reason=#{reason}"
    end

    def finish(created:)
      @processed = @total
      @created = created
      report('complete', @clock.call)
    end

    protected

    def report(state, now)
      elapsed = now - @started_at
      rate = elapsed > 0 ? @processed / elapsed : 0.0
      percentage = @total > 0 ? 100.0 * @processed / @total : 100.0
      eta = if @processed >= @total
              0.0
            elsif rate > 0
              (@total - @processed) / rate
            end
      fields = [
        "processed=#{@processed}/#{@total}",
        "percentage=#{format('%.1f', percentage)}%",
        "elapsed=#{format('%.1f', elapsed)}s",
        "rate=#{format('%.1f', rate)} rows/s",
        "eta=#{eta ? "#{format('%.1f', eta)}s" : 'unknown'}",
        "created=#{@created}"
      ]
      @io.puts "#{@label}: #{state} #{fields.join(' ')}"
      @last_report_at = now
    end
  end
end
