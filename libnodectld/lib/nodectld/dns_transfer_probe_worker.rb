require 'base64'
require 'ipaddr'
require 'tempfile'

module NodeCtld
  class DnsTransferProbeWorker
    CommandResult = Struct.new(:exitstatus, :stdout, :stderr, :limit)
    MAX_DIAGNOSTIC_BYTES = 2048
    MAX_JOB_BYTES = 64 * 1024
    MAX_RESULT_BYTES = 64 * 1024
    MAX_AXFR_BYTES = 256 * 1024 * 1024
    MAX_PROBE_TIMEOUT = 60
    MAX_AXFR_TIMEOUT = 10 * 60
    JOB_KEYS = %w[
      zone_name
      primary_addr
      source_addr
      tsig_key
      loaded_serial
      force_axfr
      probe_timeout
      axfr_timeout
      axfr_max_bytes
    ].freeze
    COMMAND_KEYS = %w[dig_command checkconf_command].freeze
    TSIG_KEYS = %w[name algorithm secret].freeze

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

    def self.extract_commands!(job)
      unless job.is_a?(Hash) &&
             (job.keys - (JOB_KEYS + COMMAND_KEYS)).empty? &&
             (JOB_KEYS + COMMAND_KEYS - job.keys).empty?
        raise ArgumentError, 'probe job has an invalid schema'
      end

      COMMAND_KEYS.to_h do |key|
        value = job.delete(key)
        unless value.is_a?(String) && value.start_with?('/') &&
               value.bytesize <= 4096 && !value.include?("\0")
          raise ArgumentError, "#{key} must be an absolute command path"
        end

        [key, value]
      end
    end

    def self.validate_job!(job)
      new.send(:validate_job!, job)
      true
    end

    def initialize(dig_command: 'dig', checkconf_command: 'named-checkconf')
      unless dig_command.is_a?(String) && !dig_command.empty? &&
             checkconf_command.is_a?(String) && !checkconf_command.empty?
        raise ArgumentError, 'probe commands must be non-empty strings'
      end

      @dig_command = dig_command
      @checkconf_command = checkconf_command
    end

    def run(job)
      validate_job!(job)

      return local_failure('No matching transfer source address') if @source_addr.nil?

      if @force_axfr || @loaded_serial.nil?
        return probe_axfr
      end

      soa = run_dig('SOA', max_bytes: 256 * 1024)
      failure = dig_failure(soa, 'ixfr_probe')
      return failure if failure

      unless authoritative_response?(soa.stdout)
        return failed_result(
          'ixfr_probe',
          'primary',
          'not_authoritative',
          'SOA response was not authoritative'
        )
      end

      primary_serial = parse_single_answer_soa_serial(soa.stdout)
      if primary_serial.nil?
        return failed_result(
          'ixfr_probe',
          'primary',
          'protocol_error',
          'SOA response did not contain a serial'
        )
      end

      ixfr = run_dig("IXFR=#{primary_serial}", max_bytes: 1024 * 1024)
      rcode = dig_rcode(ixfr.stdout)
      if ixfr.limit.nil? && ixfr.exitstatus == 0 && %w[FORMERR NOTIMP].include?(rcode)
        return probe_axfr
      end

      failure = dig_failure(ixfr, 'ixfr_probe')
      return failure if failure

      ixfr_serial = parse_single_answer_soa_serial(ixfr.stdout)
      unless authoritative_response?(ixfr.stdout) && ixfr_serial
        return probe_axfr if authoritative_response?(ixfr.stdout)

        return failed_result(
          'ixfr_probe',
          'primary',
          'protocol_error',
          'IXFR response did not contain an SOA record'
        )
      end

      if serial_behind?(ixfr_serial, @loaded_serial)
        failed_result(
          'ixfr_probe',
          'primary',
          'stale',
          "Primary serial #{ixfr_serial} is behind secondary serial #{@loaded_serial}",
          primary_serial: ixfr_serial,
          secondary_serial: @loaded_serial
        )
      else
        success_result(
          'ixfr_probe',
          "Transfer readiness confirmed at serial #{ixfr_serial}",
          primary_serial: ixfr_serial,
          secondary_serial: @loaded_serial
        )
      end
    end

    protected

    def probe_axfr
      result = run_dig(
        'AXFR',
        max_bytes: @axfr_max_bytes,
        timeout: @axfr_timeout
      )
      failure = dig_failure(result, 'axfr_probe')
      return failure if failure

      zone_text = axfr_zone_text(result.stdout)

      Tempfile.create(['dns-transfer-probe-', '.zone']) do |zone_file|
        zone_file.chmod(0o600)
        zone_file.write(zone_text)
        zone_file.flush

        Tempfile.create(['dns-transfer-probe-', '.conf']) do |config_file|
          config_file.chmod(0o600)
          config_file.write(<<~CONFIG)
            options { directory "/"; };
            zone "#{@zone_name}" {
              type primary;
              file "#{zone_file.path}";
            };
          CONFIG
          config_file.flush

          validation = run_command(
            [@checkconf_command, '-z', config_file.path],
            timeout: 60,
            max_bytes: 256 * 1024
          )

          if validation.limit
            return local_failure(
              'Local zone validation could not complete',
              'axfr_probe'
            )
          end

          unless validation.exitstatus == 0
            return failed_result(
              'axfr_probe',
              'primary',
              'invalid_zone',
              'BIND rejected the transferred zone'
            )
          end
        end
      end

      primary_serial = parse_zone_soa_serial(zone_text)
      if primary_serial.nil?
        return failed_result(
          'axfr_probe',
          'primary',
          'protocol_error',
          'Validated AXFR did not contain the zone SOA'
        )
      end

      if serial_behind?(primary_serial, @loaded_serial)
        return failed_result(
          'axfr_probe',
          'primary',
          'stale',
          "Primary serial #{primary_serial} is behind secondary serial #{@loaded_serial}",
          primary_serial:,
          secondary_serial: @loaded_serial
        )
      end

      success_result(
        'axfr_probe',
        "AXFR validated successfully at serial #{primary_serial}",
        primary_serial:,
        secondary_serial: @loaded_serial
      )
    end

    def run_dig(query, max_bytes:, timeout: @probe_timeout)
      with_key_file do |key_file|
        command = [
          @dig_command, '+tcp', '+comments', '+noquestion', '+nostats', '+onesoa',
          '+time=5', '+tries=1', '-f', '-'
        ]
        command.push('-k', key_file.path) if key_file
        run_command(
          command,
          timeout:,
          max_bytes:,
          stdin_data: "@#{@primary_addr} -b #{@source_addr} #{@zone_name} #{query}\n"
        )
      end
    end

    def with_key_file
      return yield(nil) if @tsig_key.nil?

      Tempfile.create('dns-transfer-probe-key-') do |f|
        f.chmod(0o600)
        f.write(<<~KEY)
          key "#{@tsig_key.fetch('name')}" {
            algorithm #{@tsig_key.fetch('algorithm')};
            secret "#{@tsig_key.fetch('secret')}";
          };
        KEY
        f.flush
        yield(f)
      end
    end

    def run_command(command, timeout:, max_bytes:, stdin_data: nil)
      stdout_file = Tempfile.new('dns-transfer-probe-stdout-')
      stderr_file = Tempfile.new('dns-transfer-probe-stderr-')
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      read_input, write_input = IO.pipe if stdin_data
      pid = Process.spawn(
        *command,
        in: read_input || File::NULL,
        out: stdout_file,
        err: stderr_file,
        pgroup: true
      )
      read_input&.close
      if write_input
        write_input.write(stdin_data)
        write_input.close
      end
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
      read_input&.close
      write_input&.close
      stdout_file&.close!
      stderr_file&.close!
    end

    def dig_failure(result, attempt_kind)
      case result.limit
      when :timeout
        if attempt_kind == 'axfr_probe'
          return local_failure('Probe command exceeded the local time limit', attempt_kind)
        end

        return failed_result(
          attempt_kind, 'network', 'timeout', 'Probe command timed out'
        )
      when :size
        return local_failure('Probe response exceeded the local size limit', attempt_kind)
      when :local
        return local_failure(dig_diagnostic(result, nil), attempt_kind)
      end

      rcode = dig_rcode(result.stdout)
      metadata = dig_metadata(result)
      normalized = metadata.downcase
      diagnostic = dig_diagnostic(result, rcode)

      if normalized.match?(TSIG_FAILURE_PATTERN)
        return failed_result(attempt_kind, 'primary', 'tsig_error', diagnostic)
      end

      return if result.exitstatus == 0 && rcode == 'NOERROR'

      if normalized.include?('timed out') || normalized.include?('no servers could be reached')
        failed_result(attempt_kind, 'network', 'timeout', diagnostic)
      elsif normalized.match?(/network is unreachable|no route to host|connection refused|connection reset/)
        failed_result(attempt_kind, 'network', 'connection_failed', diagnostic)
      elsif rcode == 'REFUSED'
        failed_result(attempt_kind, 'primary', 'refused', diagnostic)
      elsif rcode == 'NOTAUTH'
        failed_result(attempt_kind, 'primary', 'not_authoritative', diagnostic)
      elsif rcode == 'NXDOMAIN'
        failed_result(attempt_kind, 'primary', 'not_found', diagnostic)
      elsif rcode == 'SERVFAIL'
        failed_result(attempt_kind, 'primary', 'servfail', diagnostic)
      elsif result.exitstatus.nil?
        local_failure(diagnostic, attempt_kind)
      else
        failed_result(attempt_kind, 'primary', 'protocol_error', diagnostic)
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

    def parse_single_answer_soa_serial(output)
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

      soa_serial_from_line(answer_records.first)
    end

    def parse_zone_soa_serial(output)
      output.each_line do |line|
        serial = soa_serial_from_line(line)
        return serial if serial
      end

      nil
    end

    def axfr_zone_text(output)
      output.each_line.grep(/\A\S+\s+\d+\s+IN\s+\S+\s+\S/i).join
    end

    def soa_serial_from_line(line)
      match = /\A(\S+)\s+\d+\s+IN\s+SOA\s+\S+\s+\S+\s+(\d+)\b/i.match(line)
      return if match.nil?
      return unless canonical_dns_name(match[1]) == canonical_dns_name(@zone_name)

      match[2].to_i
    end

    def canonical_dns_name(name)
      "#{name.to_s.delete_suffix('.').downcase}."
    end

    def serial_behind?(primary_serial, secondary_serial)
      return false if secondary_serial.nil? || primary_serial == secondary_serial

      ((secondary_serial - primary_serial) & 0xffff_ffff) < 0x8000_0000
    end

    def success_result(attempt_kind, message, **attrs)
      attrs.merge(
        status: 'success',
        attempt_kind:,
        message:
      )
    end

    def failed_result(attempt_kind, failure_class, reason_code, message, **attrs)
      attrs.merge(
        status: 'failed',
        attempt_kind:,
        failure_class:,
        reason_code:,
        reason: REASON_TEXT.fetch(reason_code),
        message:
      )
    end

    def local_failure(message, attempt_kind = 'ixfr_probe')
      failed_result(attempt_kind, 'local', 'probe_limit', message)
    end

    def validate_job!(job)
      unless job.is_a?(Hash) && (job.keys - JOB_KEYS).empty? &&
             (JOB_KEYS - job.keys).empty?
        raise ArgumentError, 'probe job has an invalid schema'
      end

      @zone_name = validate_zone_name(job['zone_name'])
      @primary_addr = validate_ip_address(job['primary_addr'], 'primary_addr')
      @source_addr = job['source_addr'] &&
                     validate_ip_address(job['source_addr'], 'source_addr')
      if @source_addr && @source_addr.ipv4? != @primary_addr.ipv4?
        raise ArgumentError, 'source_addr and primary_addr must use the same family'
      end

      @primary_addr = @primary_addr.to_s
      @source_addr = @source_addr&.to_s
      @tsig_key = validate_tsig_key(job['tsig_key'])
      @loaded_serial = validate_serial(job['loaded_serial'])
      unless [true, false].include?(job['force_axfr'])
        raise ArgumentError, 'force_axfr must be a boolean'
      end

      @force_axfr = job['force_axfr']
      @probe_timeout = validate_number(
        job['probe_timeout'], 'probe_timeout', MAX_PROBE_TIMEOUT
      )
      @axfr_timeout = validate_number(
        job['axfr_timeout'], 'axfr_timeout', MAX_AXFR_TIMEOUT
      )
      @axfr_max_bytes = validate_integer(
        job['axfr_max_bytes'], 'axfr_max_bytes', MAX_AXFR_BYTES
      )
    end

    def validate_zone_name(value)
      unless value.is_a?(String) && value.bytesize.between?(2, 255) &&
             value.match?(/\A(?:[A-Za-z0-9_](?:[A-Za-z0-9_-]{0,62})?\.)+\z/)
        raise ArgumentError, 'zone_name must be an absolute DNS name'
      end

      value
    end

    def validate_ip_address(value, key)
      unless value.is_a?(String) && !value.include?('/') && !value.include?('%')
        raise ArgumentError, "#{key} must be an IP address"
      end

      IPAddr.new(value)
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, "#{key} must be an IP address"
    end

    def validate_tsig_key(value)
      return if value.nil?

      unless value.is_a?(Hash) && (value.keys - TSIG_KEYS).empty? &&
             (TSIG_KEYS - value.keys).empty? &&
             value['name'].is_a?(String) &&
             value['name'].match?(/\A[A-Za-z0-9_.-]{1,255}\z/) &&
             value['algorithm'].is_a?(String) &&
             value['algorithm'].match?(/\A[a-z0-9-]{1,64}\z/) &&
             value['secret'].is_a?(String) &&
             value['secret'].bytesize.between?(1, 4096)
        raise ArgumentError, 'tsig_key has an invalid schema'
      end

      Base64.strict_decode64(value['secret'])
      value
    rescue ArgumentError
      raise ArgumentError, 'tsig_key has an invalid schema'
    end

    def validate_serial(value)
      return if value.nil?
      return value if value.is_a?(Integer) && value.between?(0, 0xffff_ffff)

      raise ArgumentError, 'loaded_serial must be a DNS serial'
    end

    def validate_number(value, key, maximum)
      unless value.is_a?(Numeric) && value.finite? &&
             value > 0 && value <= maximum
        raise ArgumentError, "#{key} is outside the supported range"
      end

      value
    end

    def validate_integer(value, key, maximum)
      unless value.is_a?(Integer) && value > 0 && value <= maximum
        raise ArgumentError, "#{key} is outside the supported range"
      end

      value
    end
  end
end
