require 'digest'
require 'fileutils'
require 'json'
require 'libosctl'
require 'open3'
require 'tempfile'

module NodeCtld
  class DnsTransferProbe
    include OsCtl::Lib::Utils::Log

    CommandResult = Struct.new(:exitstatus, :stdout, :stderr, :limit)
    MAX_DIAGNOSTIC_BYTES = 2048
    FAST_RETRY_REASON_CODES = %w[
      connection_failed
      not_authoritative
      not_found
      refused
      servfail
      timeout
      tsig_error
    ].freeze
    TSIG_FAILURE_PATTERN = Regexp.union(
      /\b(?:badkey|badsig|badtime)\b/,
      /could(?:n't| not) verify(?: tsig)? signature/,
      /tsig verify failure/,
      /signature failed/,
      /expected a tsig or sig\(0\)/,
      /tsig indicates error/
    ).freeze

    REASON_TEXT = {
      'invalid_zone' => 'The transferred zone contains errors and was rejected',
      'refused' => 'The primary DNS server refused the transfer',
      'not_authoritative' => 'The primary DNS server is not authoritative for the zone',
      'not_found' => 'The primary DNS server does not know the zone',
      'servfail' => 'The primary DNS server returned a server failure',
      'timeout' => 'The primary DNS server did not respond in time',
      'connection_failed' => 'The primary DNS server could not be reached',
      'tsig_error' => 'The transfer failed TSIG authentication',
      'protocol_error' => 'The primary DNS server returned an invalid transfer response',
      'stale' => 'The primary DNS server has an older zone serial',
      'probe_limit' => 'The transfer probe reached a local safety limit',
      'unknown' => 'The transfer probe failed'
    }.freeze

    class << self
      attr_accessor :instance
    end

    def initialize
      self.class.instance = self
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
      @mutex = Mutex.new
      @schedule = {}
      @running = {}
      @persistent = normalize_persistent_state(load_persistent_state)
    end

    def start
      @thread = Thread.new do
        loop do
          schedule_probes
          sleep(1)
        rescue StandardError => e
          log(:warn, "DNS transfer probe scheduler failed with #{e.class}: #{e.message}")
          sleep(5)
        end
      end
    end

    def request_probe(zone_name, primary_addr, full: false)
      zone = DnsConfig.instance[zone_name]
      primary = zone&.user_primary_by_addr(primary_addr)
      return if zone.nil? || primary.nil?

      key = path_key(zone, primary)
      persistent_key = persistent_path_key(key)
      @mutex.synchronize do
        @persistent[persistent_key] = { 'needs_axfr' => true } if full
        @schedule[key] = Time.now.to_f
        save_persistent_state if full
      end
    end

    def log_type
      'dns-transfer-probe'
    end

    protected

    def schedule_probes
      now = Time.now.to_f
      paths = probe_paths
      path_map = paths.to_h { |zone, primary| [path_key(zone, primary), [zone, primary]] }

      @mutex.synchronize do
        (@schedule.keys - path_map.keys).each { |key| @schedule.delete(key) }
        active_persistent = path_map.keys.map { |key| persistent_path_key(key) }.uniq
        removed_persistent = @persistent.keys - active_persistent
        removed_persistent.each { |key| @persistent.delete(key) }
        save_persistent_state if removed_persistent.any?

        path_map.each_key do |key|
          @schedule[key] ||= now + initial_delay(key) unless @running[key]
        end

        due = @schedule
              .select { |key, at| at <= now && !@running[key] }
              .sort_by { |_key, at| at }
              .first(available_slots)

        due.each do |key,|
          zone, primary = path_map.fetch(key)
          @schedule.delete(key)
          @running[key] = Thread.new { run_scheduled_probe(key, zone, primary) }
        end
      end
    end

    def run_scheduled_probe(key, zone, primary)
      event = probe(zone, primary, force_axfr: needs_axfr?(key))
      persistent_key = persistent_path_key(key)
      if event[:status] == 'failed' &&
         %w[invalid_zone protocol_error].include?(event[:reason_code])
        @mutex.synchronize do
          @persistent[persistent_key] = { 'needs_axfr' => true }
          save_persistent_state
        end
      end

      publish(event)

      @mutex.synchronize do
        if event[:status] == 'success' && event[:attempt_kind] == 'axfr_probe'
          @persistent.delete(persistent_key)
          save_persistent_state
        end

        @schedule[key] ||= Time.now.to_f + next_interval(event)
        @running.delete(key)
      end
    rescue StandardError => e
      log(:warn, "DNS transfer probe #{key} failed with #{e.class}: #{e.message}")
      @mutex.synchronize do
        @schedule[key] ||= Time.now.to_f + failure_interval
        @running.delete(key)
      end
    end

    def probe(zone, primary, force_axfr: false)
      source_addr = zone.probe_source_addr(primary.fetch('ip_addr'))
      return local_failure(zone, primary, 'No matching transfer source address') if source_addr.nil?

      if force_axfr || zone.loaded_serial.nil?
        return probe_axfr(zone, primary, source_addr)
      end

      soa = run_dig(zone, primary, source_addr, 'SOA', max_bytes: 256 * 1024)
      failure = dig_failure(zone, primary, soa, 'ixfr_probe')
      return failure if failure

      unless authoritative_response?(soa.stdout)
        return failed_event(
          zone,
          primary,
          'ixfr_probe',
          'primary',
          'not_authoritative',
          'SOA response was not authoritative'
        )
      end

      primary_serial = parse_single_answer_soa_serial(soa.stdout, zone.name)
      if primary_serial.nil?
        return failed_event(
          zone,
          primary,
          'ixfr_probe',
          'primary',
          'protocol_error',
          'SOA response did not contain a serial'
        )
      end

      ixfr = run_dig(
        zone,
        primary,
        source_addr,
        "IXFR=#{primary_serial}",
        max_bytes: 1024 * 1024
      )
      rcode = dig_rcode(ixfr.stdout)
      if ixfr.limit.nil? && ixfr.exitstatus == 0 && %w[FORMERR NOTIMP].include?(rcode)
        return probe_axfr(zone, primary, source_addr)
      end

      failure = dig_failure(zone, primary, ixfr, 'ixfr_probe')
      return failure if failure

      ixfr_serial = parse_single_answer_soa_serial(ixfr.stdout, zone.name)
      unless authoritative_response?(ixfr.stdout) && ixfr_serial
        return probe_axfr(zone, primary, source_addr) if authoritative_response?(ixfr.stdout)

        return failed_event(
          zone,
          primary,
          'ixfr_probe',
          'primary',
          'protocol_error',
          'IXFR response did not contain an SOA record'
        )
      end

      if serial_behind?(ixfr_serial, zone.loaded_serial)
        failed_event(
          zone,
          primary,
          'ixfr_probe',
          'primary',
          'stale',
          "Primary serial #{ixfr_serial} is behind secondary serial #{zone.loaded_serial}",
          primary_serial: ixfr_serial,
          secondary_serial: zone.loaded_serial
        )
      else
        success_event(
          zone,
          primary,
          'ixfr_probe',
          "Transfer readiness confirmed at serial #{ixfr_serial}",
          primary_serial: ixfr_serial,
          secondary_serial: zone.loaded_serial
        )
      end
    end

    def probe_axfr(zone, primary, source_addr)
      result = run_dig(
        zone,
        primary,
        source_addr,
        'AXFR',
        max_bytes: axfr_max_bytes,
        timeout: axfr_timeout
      )
      failure = dig_failure(zone, primary, result, 'axfr_probe')
      return failure if failure

      zone_text = axfr_zone_text(result.stdout)

      Tempfile.create(['dns-transfer-probe-', '.zone']) do |zone_file|
        zone_file.chmod(0o600)
        zone_file.write(zone_text)
        zone_file.flush

        validation = run_command(
          ['named-checkzone', '-q', zone.name, zone_file.path],
          timeout: 60,
          max_bytes: 256 * 1024
        )

        if validation.limit
          return local_failure(
            zone,
            primary,
            'Local zone validation could not complete',
            'axfr_probe'
          )
        end

        unless validation.exitstatus == 0
          return failed_event(
            zone,
            primary,
            'axfr_probe',
            'primary',
            'invalid_zone',
            'named-checkzone rejected the transferred zone'
          )
        end
      end

      primary_serial = parse_zone_soa_serial(zone_text, zone.name)
      if primary_serial.nil?
        return failed_event(
          zone,
          primary,
          'axfr_probe',
          'primary',
          'protocol_error',
          'Validated AXFR did not contain the zone SOA'
        )
      end

      if serial_behind?(primary_serial, zone.loaded_serial)
        return failed_event(
          zone,
          primary,
          'axfr_probe',
          'primary',
          'stale',
          "Primary serial #{primary_serial} is behind secondary serial #{zone.loaded_serial}",
          primary_serial:,
          secondary_serial: zone.loaded_serial
        )
      end

      serial_message = primary_serial ? " at serial #{primary_serial}" : nil
      success_event(
        zone,
        primary,
        'axfr_probe',
        "AXFR validated successfully#{serial_message}",
        primary_serial:,
        secondary_serial: zone.loaded_serial
      )
    end

    def run_dig(zone, primary, source_addr, query, max_bytes:, timeout: probe_timeout)
      with_key_file(primary['tsig_key']) do |key_file|
        command = [
          'dig', '+tcp', '+comments', '+noquestion', '+nostats', '+onesoa',
          '+time=5', '+tries=1', '-b', source_addr, "@#{primary.fetch('ip_addr')}",
          zone.name, query
        ]
        command.push('-k', key_file.path) if key_file
        run_command(command, timeout:, max_bytes:)
      end
    end

    def with_key_file(tsig_key)
      return yield(nil) if tsig_key.nil?

      Tempfile.create('dns-transfer-probe-key-') do |f|
        f.chmod(0o600)
        f.write(<<~KEY)
          key "#{tsig_key.fetch('name')}" {
            algorithm #{tsig_key.fetch('algorithm')};
            secret "#{tsig_key.fetch('secret')}";
          };
        KEY
        f.flush
        yield(f)
      end
    end

    def run_command(command, timeout:, max_bytes:)
      stdout_file = Tempfile.new('dns-transfer-probe-stdout-')
      stderr_file = Tempfile.new('dns-transfer-probe-stderr-')
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      pid = Process.spawn(*command, out: stdout_file, err: stderr_file, pgroup: true)
      limit = nil
      status = nil

      loop do
        waited_pid, status = Process.waitpid2(pid, Process::WNOHANG)
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        if elapsed >= timeout
          limit = :timeout
        elsif stdout_file.size + stderr_file.size > max_bytes
          limit = :size
        end

        break if waited_pid

        if limit
          begin
            Process.kill('KILL', -pid)
          rescue Errno::ESRCH
            # The command exited between waitpid(WNOHANG) and the limit check.
          end
          begin
            _waited_pid, status = Process.waitpid2(pid)
          rescue Errno::ECHILD
            # The child was already reaped; the local limit still determines
            # the probe result.
          end
          break
        end

        sleep(0.05)
      end

      stdout_file.rewind
      stderr_file.rewind
      CommandResult.new(
        exitstatus: status&.exitstatus,
        stdout: stdout_file.read(max_bytes + 1),
        stderr: stderr_file.read(256 * 1024),
        limit:
      )
    rescue Errno::ENOENT => e
      CommandResult.new(exitstatus: nil, stdout: '', stderr: e.message, limit: :local)
    ensure
      stdout_file&.close!
      stderr_file&.close!
    end

    def dig_failure(zone, primary, result, attempt_kind)
      case result.limit
      when :timeout
        if attempt_kind == 'axfr_probe'
          return local_failure(zone, primary, 'Probe command exceeded the local time limit', attempt_kind)
        end

        return failed_event(
          zone, primary, attempt_kind, 'network', 'timeout', 'Probe command timed out'
        )
      when :size
        return local_failure(zone, primary, 'Probe response exceeded the local size limit', attempt_kind)
      when :local
        return local_failure(zone, primary, dig_diagnostic(result, nil), attempt_kind)
      end

      rcode = dig_rcode(result.stdout)
      metadata = dig_metadata(result)
      normalized = metadata.downcase
      diagnostic = dig_diagnostic(result, rcode)

      if normalized.match?(TSIG_FAILURE_PATTERN)
        return failed_event(zone, primary, attempt_kind, 'primary', 'tsig_error', diagnostic)
      end

      return if result.exitstatus == 0 && rcode == 'NOERROR'

      if normalized.include?('timed out') || normalized.include?('no servers could be reached')
        failed_event(zone, primary, attempt_kind, 'network', 'timeout', diagnostic)
      elsif normalized.match?(/network is unreachable|no route to host|connection refused|connection reset/)
        failed_event(zone, primary, attempt_kind, 'network', 'connection_failed', diagnostic)
      elsif rcode == 'REFUSED'
        failed_event(zone, primary, attempt_kind, 'primary', 'refused', diagnostic)
      elsif rcode == 'NOTAUTH'
        failed_event(zone, primary, attempt_kind, 'primary', 'not_authoritative', diagnostic)
      elsif rcode == 'NXDOMAIN'
        failed_event(zone, primary, attempt_kind, 'primary', 'not_found', diagnostic)
      elsif rcode == 'SERVFAIL'
        failed_event(zone, primary, attempt_kind, 'primary', 'servfail', diagnostic)
      elsif result.exitstatus.nil?
        local_failure(zone, primary, diagnostic, attempt_kind)
      else
        failed_event(zone, primary, attempt_kind, 'primary', 'protocol_error', diagnostic)
      end
    end

    def dig_metadata(result)
      comments = result.stdout.to_s.each_line.select { |line| line.start_with?(';;') }
      [comments.join, result.stderr].join("\n")
    end

    def dig_diagnostic(result, rcode)
      summary = ["dig exit=#{result.exitstatus || 'unknown'}"]
      summary << "rcode=#{rcode}" if rcode

      stderr = result.stderr.to_s
                     .encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
                     .gsub(/[[:cntrl:]&&[^\n\t]]/, '?')
                     .strip
      unless stderr.empty?
        summary << stderr.byteslice(0, MAX_DIAGNOSTIC_BYTES).scrub('?')
      end
      summary.join(': ')
    end

    def dig_rcode(output)
      output[/status:\s*([A-Z0-9]+),/i, 1]&.upcase
    end

    def authoritative_response?(output)
      flags = output[/;;\s+flags:\s*([^;]*);/i, 1]
      flags.to_s.split.include?('aa')
    end

    def parse_single_answer_soa_serial(output, zone_name)
      answer_count = output[/\bANSWER:\s*(\d+)\b/i, 1]
      return unless answer_count == '1'

      in_answer = false
      answer_records = []

      output.each_line do |line|
        if line.start_with?(';; ANSWER SECTION:')
          in_answer = true
          next
        elsif line.start_with?(';;')
          in_answer = false
          next
        end

        next unless in_answer
        next if line.strip.empty?

        answer_records << line
      end

      return unless answer_records.length == 1

      soa_serial_from_line(answer_records.first, zone_name)
    end

    def parse_zone_soa_serial(output, zone_name)
      output.each_line do |line|
        serial = soa_serial_from_line(line, zone_name)
        return serial if serial
      end

      nil
    end

    def axfr_zone_text(output)
      records = output.each_line.grep(/\A\S+\s+\d+\s+IN\s+\S+\s+\S/i)
      records.join
    end

    def soa_serial_from_line(line, zone_name)
      match = /\A(\S+)\s+\d+\s+IN\s+SOA\s+\S+\s+\S+\s+(\d+)\b/i.match(line)
      return if match.nil?
      return unless canonical_dns_name(match[1]) == canonical_dns_name(zone_name)

      match[2].to_i
    end

    def canonical_dns_name(name)
      "#{name.to_s.delete_suffix('.').downcase}."
    end

    def serial_behind?(primary_serial, secondary_serial)
      return false if secondary_serial.nil? || primary_serial == secondary_serial

      ((secondary_serial - primary_serial) & 0xffff_ffff) < 0x8000_0000
    end

    def success_event(zone, primary, attempt_kind, message, **attrs)
      build_event(zone, primary, 'success', attempt_kind, message:, **attrs)
    end

    def failed_event(
      zone,
      primary,
      attempt_kind,
      failure_class,
      reason_code,
      message,
      **attrs
    )
      build_event(
        zone,
        primary,
        'failed',
        attempt_kind,
        failure_class:,
        reason_code:,
        reason: REASON_TEXT.fetch(reason_code),
        message:,
        **attrs
      )
    end

    def local_failure(zone, primary, message, attempt_kind = 'ixfr_probe')
      failed_event(zone, primary, attempt_kind, 'local', 'probe_limit', message)
    end

    def build_event(zone, primary, status, attempt_kind, **attrs)
      time = Time.now.to_i
      event = attrs.merge(
        name: zone.name,
        dns_server_zone_id: zone.id,
        dns_zone_transfer_id: primary.fetch('id'),
        configuration_generation: zone.primary_transfer_generation,
        time:,
        status:,
        attempt_kind:,
        primary_addr: primary.fetch('ip_addr'),
        source_cursor: nil,
        raw_message: nil
      )
      event[:event_key] = Digest::SHA256.hexdigest(
        [
          $CFG.get(:vpsadmin, :node_id), zone.id, primary.fetch('id'),
          zone.primary_transfer_generation, time, status, attempt_kind,
          event[:failure_class], event[:reason_code], event[:primary_serial],
          event[:secondary_serial], event[:message]
        ].join("\0")
      )
      event
    end

    def publish(event)
      NodeBunny.publish_wait(
        @exchange,
        { events: [event] }.to_json,
        content_type: 'application/json',
        routing_key: 'dns_transfer_logs'
      )
    end

    def probe_paths
      DnsConfig.instance.zones.flat_map do |zone|
        next [] unless zone.enabled && zone.source == 'external_source' &&
                       zone.type == 'secondary_type' && zone.primary_transfer_generation

        zone.user_primaries.map { |primary| [zone, primary] }
      end
    end

    def path_key(zone, primary)
      "#{zone.id}:#{primary.fetch('id')}:#{zone.primary_transfer_generation}"
    end

    def persistent_path_key(key)
      key.split(':', 3).first(2).join(':')
    end

    def initial_delay(key)
      minimum = $CFG.get(:dns_server, :status_interval)
      window = [healthy_interval - minimum, 1].max
      minimum + (Digest::SHA256.hexdigest(key)[0, 8].to_i(16) % window)
    end

    def available_slots
      [probe_concurrency - @running.size, 0].max
    end

    def next_interval(event)
      if event[:status] == 'failed' &&
         (event[:failure_class] == 'network' ||
          FAST_RETRY_REASON_CODES.include?(event[:reason_code]))
        failure_interval
      else
        healthy_interval
      end
    end

    def needs_axfr?(key)
      @mutex.synchronize do
        @persistent.dig(persistent_path_key(key), 'needs_axfr') == true
      end
    end

    def probe_concurrency
      $CFG.get(:dns_server, :transfer_probe_concurrency)
    end

    def healthy_interval
      $CFG.get(:dns_server, :transfer_probe_interval)
    end

    def failure_interval
      $CFG.get(:dns_server, :transfer_probe_failure_interval)
    end

    def probe_timeout
      $CFG.get(:dns_server, :transfer_probe_timeout)
    end

    def axfr_timeout
      $CFG.get(:dns_server, :transfer_probe_axfr_timeout)
    end

    def axfr_max_bytes
      $CFG.get(:dns_server, :transfer_probe_axfr_max_bytes)
    end

    def state_file
      $CFG.get(:dns_server, :transfer_probe_state_file)
    end

    def load_persistent_state
      JSON.parse(File.read(state_file))
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def normalize_persistent_state(state)
      state.each_with_object({}) do |(key, value), ret|
        persistent_key = persistent_path_key(key)
        ret[persistent_key] = value if value['needs_axfr'] == true
      end
    end

    def save_persistent_state
      FileUtils.mkdir_p(File.dirname(state_file))
      tmp = "#{state_file}.#{$$}.tmp"
      File.write(tmp, "#{JSON.generate(@persistent)}\n")
      File.chmod(0o600, tmp)
      File.rename(tmp, state_file)
    end
  end
end
