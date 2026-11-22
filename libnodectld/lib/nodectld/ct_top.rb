require 'json'
require 'libosctl'

module NodeCtld
  # Interface to `osctl ct top`
  class CtTop
    include OsCtl::Lib::Utils::Log

    MAX_FRAME_BYTES = 16 * 1024 * 1024

    class Sample
      ENVELOPE_FIELDS = %i[epoch sequence collectors complete invalid_reason sample_started_monotonic_ns
                           sample_completed_monotonic_ns measurement_window_started_monotonic_ns
                           measurement_window_completed_monotonic_ns previous_sample_started_monotonic_ns
                           inventory_complete state_counts loadavg containers].freeze
      ROW_FIELDS = %i[pool id group_path init_pid init_start_time_ticks run_verified cpu_usage cpu_limit cpu_limit_state
                      memory memory_limit memory_limit_state nproc loadavg cpu_baseline_sequence
                      cpu_window_started_monotonic_ns errors].freeze
      METRIC_ERROR_FIELDS = %i[run cpu_usage memory nproc loadavg cpu_limit memory_limit].freeze

      attr_reader :epoch, :sequence, :started, :completed

      def initialize(packet, rate:)
        @budget = rate.to_f * 1_000_000_000
        return unless packet.is_a?(Hash) && packet[:top_schema].eql?(2) && !packet.has_key?(:observation)

        @data = packet

        @epoch, @sequence, @started, @completed, @previous_started = @data.values_at(
          :epoch, :sequence, :sample_started_monotonic_ns, :sample_completed_monotonic_ns,
          :previous_sample_started_monotonic_ns
        )
        @rows = @data[:containers].grep(Hash).group_by { |row| row.values_at(:pool, :id) } if @data[:containers].is_a?(Array)
      end

      def valid?(now_ns:, previous: nil)
        return false unless @rows && valid_envelope?(now_ns) && valid_link?(previous) && valid_host? && valid_inventory?

        !@data[:complete] || valid_complete?
      end

      def usage(ct, start_ticks:, now_ns:)
        rows = @rows[[ct.pool, ct.id]]
        return unless rows&.one?

        row = rows.first
        return unless fresh?(now_ns) && valid_row?(row) && cpu_window?(row)
        return unless row.values_at(:group_path, :init_pid, :init_start_time_ticks) == [ct[:group_path], ct.init_pid, start_ticks]

        cpu, memory, nproc = row.values_at(:cpu_usage, :memory, :nproc)
        return unless nonnegative?(cpu) && nonnegative?(memory) && nonnegative_integer?(nproc)

        [cpu, memory, nproc]
      end

      protected

      def valid_envelope?(now_ns)
        return false unless ENVELOPE_FIELDS.all? { |key| @data.has_key?(key) }
        return false unless epoch.is_a?(String) && !epoch.empty? && positive_integer?(sequence)
        return false unless positive_integer?(started) && positive_integer?(completed) && started <= completed && fresh?(now_ns)
        return false unless @data[:measurement_window_completed_monotonic_ns].eql?(completed) && boolean?(@data[:inventory_complete])
        return false unless sequence == 1 ? @previous_started.nil? : positive_integer?(@previous_started) && @previous_started < started

        collectors = @data[:collectors]
        return false unless collectors.is_a?(Hash) && %i[netif zfs iostat].all? { |key| boolean?(collectors[key]) }

        baseline = @data[:measurement_window_started_monotonic_ns]
        if @data[:complete] == true
          @data[:invalid_reason].nil? && positive_integer?(baseline) && baseline.eql?(@previous_started) && completed - baseline <= @budget * 2
        else
          @data[:complete] == false && baseline.nil? && @data[:invalid_reason].is_a?(String) && !@data[:invalid_reason].empty?
        end
      end

      def valid_complete?
        @data[:inventory_complete] && valid_load?(@data[:loadavg]) && @data[:containers][0...-1].all? do |row|
          valid_row?(row) && cpu_window?(row) && nonnegative?(row[:cpu_usage]) && nonnegative?(row[:memory]) &&
            valid_load?(row[:loadavg]) && !row.values_at(:cpu_limit_state, :memory_limit_state).include?('unknown')
        end
      end

      def valid_link?(previous)
        return true unless previous
        return false unless epoch == previous.epoch && sequence > previous.sequence && started > previous.completed

        sequence == previous.sequence + 1 ? @previous_started == previous.started : @previous_started > previous.completed
      end

      def valid_host?
        host = @data[:containers].last
        return false unless host.is_a?(Hash) && host.values_at(:pool, :id, :init_pid, :init_start_time_ticks) == [nil, '[host]', nil, nil]
        return false unless %i[pool init_pid init_start_time_ticks loadavg].all? { |key| host.has_key?(key) }
        return false unless host[:loadavg] == @data[:loadavg] && @data[:containers].one? { |row| row.is_a?(Hash) && row[:id] == '[host]' }

        host[:loadavg].nil? || valid_load?(host[:loadavg])
      end

      def valid_inventory?
        counts = @data[:state_counts]
        return !@data[:inventory_complete] if counts.nil?
        return false unless counts.is_a?(Hash) && counts.all? { |key, n| !key.to_s.empty? && nonnegative_integer?(n) }
        return true unless @data[:inventory_complete]

        rows = @data[:containers][0...-1]
        counts.fetch(:running, 0) == rows.length && @rows.values.all?(&:one?) && rows.all? { |row| verified_identity?(row) }
      end

      def fresh?(now_ns)
        @budget > 0 && @budget.finite? && completed <= now_ns &&
          now_ns - completed <= @budget && completed - started <= @budget
      end

      def verified_identity?(row)
        row.is_a?(Hash) && row[:run_verified] == true &&
          %i[pool id group_path].all? { |key| row[key].is_a?(String) && !row[key].empty? } &&
          %i[init_pid init_start_time_ticks].all? { |key| positive_integer?(row[key]) }
      end

      def valid_row?(row)
        verified_identity?(row) && ROW_FIELDS.all? { |key| row.has_key?(key) } && consistent_row_errors?(row) &&
          %i[cpu_limit memory_limit].all? { |field| valid_limit?(row, field) } &&
          (row[:loadavg].nil? || valid_load?(row[:loadavg])) && (row[:nproc].nil? || nonnegative_integer?(row[:nproc]))
      end

      def valid_limit?(row, field)
        value = row[field]
        case row[:"#{field}_state"]
        when 'limited' then nonnegative?(value) && value > 0
        when 'unlimited', 'unknown' then value.nil?
        else false
        end
      end

      def cpu_window?(row)
        sequence > 1 && row[:cpu_baseline_sequence].eql?(sequence - 1) &&
          row[:cpu_window_started_monotonic_ns].eql?(@previous_started) && completed - @previous_started <= @budget * 2
      end

      def consistent_row_errors?(row)
        errors = row[:errors]
        return false unless errors.is_a?(Hash)

        # Completeness covers the action core, not every reporting field.
        # Even a partial row cannot claim both a reading and its own error.
        METRIC_ERROR_FIELDS.all? do |field|
          next true unless errors.has_key?(field)

          reason = errors[field]
          (@data[:complete] == false || field == :nproc) && reason.is_a?(String) && !reason.empty? && error_fields_unavailable?(field, row)
        end
      end

      def error_fields_unavailable?(field, row)
        return false unless row[field].nil?

        case field
        when :run then row[:run_verified] == false
        when :cpu_usage then row[:cpu_baseline_sequence].nil? && row[:cpu_window_started_monotonic_ns].nil?
        when :cpu_limit, :memory_limit then row[:"#{field}_state"] == 'unknown'
        else true
        end
      end

      def valid_load?(values)
        values.is_a?(Array) && values.length == 3 && values.all? { |v| nonnegative?(v) }
      end

      def boolean?(value)
        [true, false].include?(value)
      end

      def positive_integer?(value)
        value.is_a?(Integer) && value > 0
      end

      def nonnegative?(value)
        value.is_a?(Numeric) && value.finite? && value >= 0
      end

      def nonnegative_integer?(value)
        value.is_a?(Integer) && value >= 0
      end
    end

    def initialize
      @retired_epochs = {}
      @mutex = Mutex.new
      @refresher = Thread.new do
        loop do
          sleep(10)

          sync do
            next if !pid || !@refresh || @refresh > Time.now

            log(:info, 'Refreshing VPS statuses')
            begin
              Process.kill('USR1', pid)
            rescue Errno::ESRCH
              # The child may have exited just before the refresh.
            end
            @refresh = false
          end
        end
      end
    end

    # @param rate [Integer] refresh frequency in seconds
    # @yieldparam [Sample] data from ct top, including the original frame envelope
    def monitor(rate, &)
      @rate = rate

      until stop?
        run(&)

        break if stop?

        sleep(1)
      end
    end

    def refresh
      # Refresh VPS statuses in 3 seconds. This should give `osctl ct top`
      # controller by {CtTop} to register newly started VPSes.
      sync { @refresh = Time.now + 3 }
    end

    def stop
      sync { @stop = true }
      pipe&.close unless pipe&.closed?
      @refresher.terminate
    end

    def log_type
      'ct top'
    end

    protected

    attr_reader :rate, :pipe, :pid

    def run
      r, w = IO.pipe
      @pipe = r
      pid = Process.spawn('osctl', '-j', 'ct', 'top', '--rate', rate.to_s, '--no-iostat', '--no-processes',
                          out: w, close_others: true)
      w.close

      log(:info, "Started with pid #{pid}")

      sync { @pid = pid }

      epoch = nil
      read_samples(r) do |sample|
        epoch = sample.epoch
        sync { @refresh = false }
        yield(sample)
      end
      sync { @pid = nil }
      _, status = Process.wait2(pid)
      @retired_epochs[epoch] = true if epoch
      log(:info, "ct top exited (#{status.exitstatus.inspect})")
    ensure
      sync { @pid = nil }
      w&.close unless w&.closed?
      r&.close unless r&.closed?
    end

    def read_samples(io)
      previous = nil
      rejected = false
      while (line = io.gets("\n", MAX_FRAME_BYTES + 1))
        if line.bytesize > MAX_FRAME_BYTES || !line.end_with?("\n")
          line = io.gets("\n", MAX_FRAME_BYTES + 1) until line.nil? || line.end_with?("\n")
          sample = nil
        else
          sample = parse_sample(line)
        end
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        unless sample && !@retired_epochs.has_key?(sample.epoch) && sample.valid?(previous:, now_ns: now)
          log(:warn, 'Ignoring invalid or stale ct top output') unless rejected
          rejected = true
          next
        end

        previous = sample
        rejected = false
        yield(sample)
      end
    rescue IOError
      raise unless stop?
    end

    def parse_sample(line)
      Sample.new(JSON.parse(line, symbolize_names: true), rate:)
    rescue JSON::ParserError
      nil
    end

    def stop?
      sync { @stop }
    end

    def sync(&)
      @mutex.synchronize(&)
    end
  end
end
