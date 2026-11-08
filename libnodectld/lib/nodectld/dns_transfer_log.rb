require 'digest'
require 'fileutils'
require 'ipaddress'
require 'json'
require 'libosctl'
require 'shellwords'
require 'time'

module NodeCtld
  class DnsTransferLog
    include OsCtl::Lib::Utils::Log

    MAX_TRANSFER_ATTEMPTS = 256
    # BIND's shipped max-transfer-time-in is 120 minutes. Keep correlation a
    # little longer so the terminal status and journal ordering can follow a
    # valid large transfer without losing its primary address.
    TRANSFER_ATTEMPT_TTL = 130 * 60

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
      'unknown' => 'The transfer failed'
    }.freeze

    # Result texts returned by BIND's DNS message parser for malformed wire
    # data. xfrin uses these results as terminal transfer statuses, so they are
    # evidence about the remote response rather than an unspecified local
    # failure. Keep the strings aligned with lib/isc/result.c.
    PROTOCOL_FAILURE_RESULTS = [
      'label too long',
      'bad escape',
      'empty label',
      'bad dotted quad',
      'unknown class/type',
      'bad label type',
      'bad compression pointer',
      'too many hops',
      'extra input text',
      'extra input data',
      'text too long',
      'not at top of zone',
      'syntax error',
      'bad checksum',
      'bad ipv6 address',
      'no owner',
      'no ttl',
      'bad class',
      'name too long',
      'bad ttl',
      'bad owner name (check-names)',
      'bad name (check-names)',
      'malformed opt option',
      'unexpected message id',
      'response with mismatched query id',
      'expected a response'
    ].freeze

    attr_reader :cursor_file

    def initialize
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
      @cursor_file = $CFG.get(:dns_server, :transfer_log_cursor_file)
      @transfer_attempts = {}
    end

    def start
      @thread = Thread.new do
        loop do
          read_journal
        rescue StandardError => e
          log(:warn, "DNS transfer log reader failed with #{e.class}: #{e.message}")
          sleep(5)
        end
      end
    end

    def log_type
      'dns-transfer-log'
    end

    protected

    def read_journal
      command = journal_command
      log(:info, "Reading BIND transfer logs using #{Shellwords.join(command)}")

      IO.popen(command, err: %i[child out]) do |io|
        io.each_line do |line|
          process_journal_line(line)
        end
      end
    end

    def journal_command
      cmd = [$CFG.get(:dns_server, :transfer_log_command)]
      Array($CFG.get(:dns_server, :transfer_log_identifiers)).each do |identifier|
        cmd.push('-t', identifier)
      end

      unit = $CFG.get(:dns_server, :transfer_log_unit)
      cmd.push('-u', unit) if unit

      cmd.push('-o', 'json', '-f')

      if current_cursor
        cmd << "--after-cursor=#{current_cursor}"
      else
        cmd.push('-n', '0')
      end

      cmd
    end

    def process_journal_line(line)
      entry = JSON.parse(line)
      cursor = entry['__CURSOR']
      message = entry['MESSAGE'].to_s
      dns_config = DnsConfig.instance
      event_time = journal_time(entry)
      event = parse_message(message, event_time:, dns_config:)
      zone = event && dns_config[event[:name]]

      prune_unmanaged_attempts(dns_config)

      if event && zone
        enrich_event(event, zone) unless event.delete(:association_snapshotted)
        event.update(
          time: event_time,
          message: event[:message] || message,
          raw_message: message,
          source_cursor: cursor,
          event_key: event_key(cursor, event, message)
        )

        schedule_probe(event, zone)
        publish(event)
      end

      save_cursor(cursor) if cursor && @transfer_attempts.empty?
    rescue JSON::ParserError
      log(:warn, "Skipping non-JSON journal line: #{line.strip}")
    end

    def publish(event)
      NodeBunny.publish_wait(
        @exchange,
        { events: [event] }.to_json,
        content_type: 'application/json',
        routing_key: 'dns_transfer_logs'
      )
    end

    def enrich_event(event, zone)
      event[:dns_server_zone_id] = zone.id
      event[:configuration_generation] = zone.primary_transfer_generation

      primary = user_primary(zone, event[:primary_addr])
      event[:dns_zone_transfer_id] = primary && primary['id']
    end

    def schedule_probe(event, zone)
      return unless event[:status] == 'failed' && event[:dns_zone_transfer_id]

      probe = DnsTransferProbe.instance
      return if probe.nil?

      probe.request_probe(
        zone.name,
        event[:primary_addr],
        full: %w[invalid_zone protocol_error].include?(event[:reason_code])
      )
    end

    def user_primary(zone, addr)
      return if addr.nil?

      normalized_addr = normalize_ip_address(addr)
      zone.user_primaries.find do |primary|
        normalize_ip_address(primary['ip_addr']) == normalized_addr
      end
    end

    def normalize_ip_address(addr)
      IPAddress.parse(addr).to_s
    rescue ArgumentError, IPAddress::InvalidAddressError
      nil
    end

    def current_cursor
      return if cursor_file.nil?
      return unless File.exist?(cursor_file)

      cursor = File.read(cursor_file).strip
      cursor.empty? ? nil : cursor
    end

    def save_cursor(cursor)
      return if cursor_file.nil?

      FileUtils.mkdir_p(File.dirname(cursor_file))
      tmp = "#{cursor_file}.#{$$}.tmp"
      File.write(tmp, "#{cursor}\n")
      File.rename(tmp, cursor_file)
    end

    def journal_time(entry)
      usec = entry['__REALTIME_TIMESTAMP'] || entry['_SOURCE_REALTIME_TIMESTAMP']
      return Time.now.to_i if usec.nil?

      (usec.to_i / 1_000_000.0).to_i
    end

    def parse_message(message, event_time: nil, dns_config: nil)
      prune_transfer_attempts

      parse_transfer_message(message, event_time:, dns_config:) ||
        parse_transferred_serial(message) ||
        parse_transferred_zone_rejection(message) ||
        parse_zone_up_to_date(message) ||
        parse_primary_behind(message) ||
        parse_refresh_failure(message) ||
        parse_zone_load_failure(message)
    end

    def parse_transfer_message(message, event_time:, dns_config:)
      match = %r{\A(?:(0x[0-9a-f]+): )?transfer of '([^']+)/IN' from ([^#\s]+)#\d+: (.+)\z}i.match(message)
      return unless match

      pointer, zone, primary_addr, body = match.captures
      key = transfer_attempt_key(pointer, zone, primary_addr)
      attempt = @transfer_attempts[key]
      if attempt && (transfer_attempt_start?(body) ||
                     !same_transfer_attempt?(attempt, zone, primary_addr))
        @transfer_attempts.delete(key)
        attempt = nil
      end

      if body.start_with?('Transfer completed:')
        return
      end

      attempt ||= remember_transfer_attempt(
        key,
        zone,
        primary_addr,
        event_time:,
        dns_config:
      )

      if (status_match = /\ATransfer status: (.+)\z/i.match(body))
        return finish_transfer_attempt(key, attempt, status_match[1].strip)
      end

      if body.match?(/failed/i)
        attempt[:failure] = body
        attempt[:updated_at] = monotonic_time
      end

      nil
    end

    def parse_zone_up_to_date(message)
      return unless %r{\Azone ([^/]+)/IN: notify from ([^#\s]+)#\d+: zone is up to date\z} =~ message

      event(
        Regexp.last_match(1),
        'success',
        attempt_kind: 'notify',
        failure_class: nil,
        primary_addr: Regexp.last_match(2),
        message: 'Zone is up to date'
      )
    end

    def parse_transferred_serial(message)
      return unless %r{\Azone ([^/]+)/IN: transferred serial (\d+)(?:: TSIG '[^']+')?\z} =~ message

      zone = Regexp.last_match(1)
      serial = Regexp.last_match(2).to_i
      attempt = latest_transfer_attempt(zone)
      return unless attempt

      attempt[:accepted_serial] = serial
      attempt[:updated_at] = monotonic_time
      @transfer_attempts.delete(attempt[:key]) if attempt[:terminal_success]

      event(
        zone,
        'success',
        attempt_kind: 'transfer',
        failure_class: nil,
        primary_addr: attempt && attempt[:primary_addr],
        serial:,
        message: "Transferred serial #{serial}"
      ).merge(attempt_association(attempt))
    end

    def parse_transferred_zone_rejection(message)
      match = %r{\Azone ([^/]+)/IN: (transferred zone (?:has \d+ SOA records|has no NS records))\z}.match(message)
      return unless match

      zone, rejection = match.captures
      attempt = latest_transfer_attempt(zone)
      if attempt
        attempt[:rejected] = true
        attempt[:updated_at] = monotonic_time
        @transfer_attempts.delete(attempt[:key]) if attempt[:terminal_success]
      end

      failed_event(
        zone,
        attempt && attempt[:primary_addr],
        rejection,
        attempt_kind: 'transfer',
        failure_class: 'primary',
        reason_code: 'invalid_zone'
      ).merge(attempt_association(attempt))
    end

    def parse_primary_behind(message)
      match = %r{
        \Azone\ ([^/]+)/IN:\ serial\ number\ \((\d+)\)\ received\ from
        \ primary\ ([^#\s]+)\#\d+\ <\ ours\ \(\d+\)\z
      }x.match(message)
      return unless match

      event(
        match[1],
        'success',
        attempt_kind: 'refresh',
        failure_class: nil,
        primary_addr: match[3],
        serial: match[2].to_i,
        message: "Primary responded with older serial #{match[2]}"
      )
    end

    def parse_refresh_failure(message)
      match = %r{\Azone ([^/]+)/IN: refresh: (.+)\z}.match(message)
      return unless match

      zone, body = match.captures
      return if refresh_fallback?(body)

      primary_addr, reason, event_failure_class = refresh_failure(body)
      return unless reason

      failed_event(
        zone,
        primary_addr,
        reason,
        attempt_kind: 'refresh',
        failure_class: event_failure_class || failure_class(reason)
      )
    end

    def parse_zone_load_failure(message)
      match = %r{\Azone ([^/]+)/IN: (loading from master file .+ failed: .+|not loaded due to errors\.)\z}.match(message)
      return unless match

      failed_event(
        match[1],
        nil,
        match[2],
        attempt_kind: 'load',
        failure_class: 'local'
      )
    end

    def finish_transfer_attempt(key, attempt, status)
      normalized = status.downcase

      if normalized == 'success'
        if attempt[:accepted_serial] || attempt[:rejected]
          @transfer_attempts.delete(key)
          return
        end

        attempt[:terminal_success] = true
        attempt[:updated_at] = monotonic_time
        return
      end

      @transfer_attempts.delete(key)
      return if normalized == 'ixfr failed'

      if normalized == 'up to date'
        return event(
          attempt[:zone],
          'success',
          attempt_kind: 'refresh',
          failure_class: nil,
          primary_addr: attempt[:primary_addr],
          message: 'Zone is up to date'
        ).merge(attempt_association(attempt))
      end

      reason = attempt[:failure] || status
      failed_event(
        attempt[:zone],
        attempt[:primary_addr],
        reason,
        attempt_kind: 'transfer'
      ).merge(attempt_association(attempt))
    end

    def failed_event(
      zone,
      primary_addr,
      reason,
      attempt_kind:,
      failure_class: failure_class(reason),
      reason_code: reason_code(reason)
    )
      event(
        zone,
        'failed',
        attempt_kind:,
        failure_class:,
        primary_addr:,
        reason_code:,
        reason: REASON_TEXT.fetch(reason_code),
        message: reason
      )
    end

    def reason_code(reason)
      normalized = reason.to_s.downcase
      protocol_result = PROTOCOL_FAILURE_RESULTS.any? do |result|
        normalized == result || normalized.end_with?(": #{result}")
      end

      if normalized.include?('bad zone') || normalized.include?('soa records') ||
         normalized.include?('no ns records') || normalized.include?('soa mismatch') ||
         normalized.include?('too many records') ||
         normalized.include?('invalid ns owner name')
        'invalid_zone'
      elsif protocol_result ||
            normalized == 'failed while receiving responses: unexpected error' ||
            normalized == 'failed while receiving responses: unexpected end of input' ||
            normalized.include?('formerr') || normalized.include?('notimp') ||
            normalized.include?('malformed') || normalized.include?('unexpected opcode') ||
            normalized.include?('referral response') || normalized.include?('nodata response') ||
            normalized.include?('truncated tcp response') ||
            normalized.include?('unable to get soa record') ||
            normalized.include?('answer soa count') ||
            normalized.include?('cname at top of zone') ||
            normalized.include?('bad class') || normalized.include?('extra input data') ||
            normalized.include?('unexpected message id') ||
            normalized.include?('response with mismatched query id') ||
            normalized.include?('expected a response') ||
            normalized.include?('unexpected rcode') ||
            normalized.include?('not at top of zone') ||
            normalized.match?(/\b(?:badvers|badcookie|notzone|yxdomain|yxrrset|nxrrset)\b/) ||
            normalized.include?('<rcode ')
        'protocol_error'
      elsif normalized.include?('connection refused') || normalized.include?('network unreachable') ||
            normalized.include?('host unreachable') || normalized.include?('network down') ||
            normalized.include?('host down') || normalized.include?('no route to host') ||
            normalized.include?('connection reset') || normalized.include?('connection failed') ||
            normalized == 'failed while receiving responses: end of file'
        'connection_failed'
      elsif normalized.include?('refused')
        'refused'
      elsif normalized.include?('notauth') || normalized.include?('not authoritative') ||
            normalized.include?('not authoritative for') || normalized.include?('non-authoritative')
        'not_authoritative'
      elsif ['nxdomain', 'failed while receiving responses: nxdomain'].include?(normalized)
        'not_found'
      elsif normalized.include?('servfail') || normalized.include?('server failure')
        'servfail'
      elsif normalized.include?('timed out') || normalized.include?('timeout')
        'timeout'
      elsif normalized.include?('tsig') || normalized.include?('badkey') ||
            normalized.include?('badsig') || normalized.include?('badtime') ||
            normalized.include?('sig(0)') ||
            normalized.include?('expected a tsig or sig(0)') ||
            normalized.include?('clocks are unsynchronized') ||
            normalized.include?('clock skew')
        'tsig_error'
      else
        'unknown'
      end
    end

    def failure_class(reason)
      normalized = reason.to_s.downcase
      code = reason_code(reason)

      if normalized.include?('shutting down') || normalized.include?('shut down') ||
         normalized.include?('operation canceled') || normalized.include?('operation cancelled') ||
         normalized == 'canceled' || normalized == 'cancelled'
        'lifecycle'
      elsif %w[connection_failed timeout].include?(code)
        'network'
      elsif code != 'unknown'
        'primary'
      elsif normalized.include?('not enough free resources') || normalized.include?('out of memory') ||
            normalized.include?('permission denied') || normalized.include?('read-only file system') ||
            normalized.include?('disk full') || normalized.include?('no space left')
        'local'
      else
        'unknown'
      end
    end

    def refresh_fallback?(body)
      body.match?(/\A(?:timeout retrying without EDNS|rcode \(.+\) retrying without EDNS)/) ||
        body.start_with?('truncated UDP answer, initiating TCP zone xfer') ||
        body.start_with?('skipped tcp fallback ')
    end

    def refresh_failure(body)
      if (match = /\Aretry limit for primary ([^#\s]+)#\d+ exceeded /.match(body))
        return [match[1], 'timed out after refresh retries', 'network']
      end

      if (match = /\Afailure trying primary ([^#\s]+)#\d+.*: (.+)\z/.match(body))
        return [match[1], match[2], nil]
      end

      if (match = /\Aunexpected rcode \(([^)]+)\) from (?:primary )?([^#\s]+)#\d+/.match(body))
        return [match[2], match[1], 'primary']
      end

      patterns = [
        /\Aunexpected opcode \(([^)]+)\) from ([^#\s]+)#\d+/,
        /\Anon-authoritative answer from primary ([^#\s]+)#\d+/,
        /\ACNAME at top of zone in primary ([^#\s]+)#\d+/,
        /\Areferral response from primary ([^#\s]+)#\d+/,
        /\ANODATA response from primary ([^#\s]+)#\d+/,
        /\Aanswer SOA count \(\d+\) != 1 from primary ([^#\s]+)#\d+/,
        /\Aunable to get SOA record from primary ([^#\s]+)#\d+/,
        /\Atruncated TCP response from primary ([^#\s]+)#\d+/
      ]

      patterns.each do |pattern|
        next unless (match = pattern.match(body))

        primary_addr = match.captures.last
        return [primary_addr, body, 'primary']
      end

      if (match = /\Askipping zone transfer as primary ([^#\s]+)#\d+ .+ unreachable/.match(body))
        return [match[1], body, 'network']
      end

      nil
    end

    def transfer_attempt_key(pointer, zone, primary_addr)
      return "pointer:#{pointer.downcase}" if pointer

      "fallback:#{normalize_zone_name(zone).downcase}\0#{primary_addr}"
    end

    def transfer_attempt_start?(body)
      body.match?(/\Aconnected(?: using)?\b/i)
    end

    def same_transfer_attempt?(attempt, zone, primary_addr)
      same_zone = attempt[:zone].casecmp?(normalize_zone_name(zone))
      old_addr = normalize_ip_address(attempt[:primary_addr]) || attempt[:primary_addr].downcase
      new_addr = normalize_ip_address(primary_addr) || primary_addr.downcase

      same_zone && old_addr == new_addr
    end

    def remember_transfer_attempt(key, zone, primary_addr, event_time:, dns_config:)
      prune_transfer_attempts
      now = monotonic_time
      association = transfer_attempt_association(
        zone,
        primary_addr,
        event_time:,
        dns_config:
      )
      attempt = {
        key:,
        zone: normalize_zone_name(zone),
        primary_addr:,
        created_at: now,
        updated_at: now,
        association:
      }
      @transfer_attempts[key] = attempt
      prune_transfer_attempts
      attempt
    end

    def transfer_attempt_association(zone_name, primary_addr, event_time:, dns_config:)
      zone = dns_config && dns_config[normalize_zone_name(zone_name)]
      return {} if zone.nil?

      association = {
        association_snapshotted: true,
        dns_server_zone_id: zone.id,
        dns_zone_transfer_id: nil,
        configuration_generation: zone.primary_transfer_generation
      }
      boundary = zone.primary_transfer_tracking_started_at
      return association if event_time.nil? || boundary.nil? || event_time <= boundary

      primary = user_primary(zone, primary_addr)
      association[:dns_zone_transfer_id] = primary && primary['id']
      association
    end

    def attempt_association(attempt)
      attempt ? attempt.fetch(:association, {}) : {}
    end

    def latest_transfer_attempt(zone)
      normalized_zone = normalize_zone_name(zone).downcase

      @transfer_attempts.values.reverse_each.find do |attempt|
        attempt[:zone].downcase == normalized_zone
      end
    end

    def prune_transfer_attempts
      cutoff = monotonic_time - TRANSFER_ATTEMPT_TTL
      @transfer_attempts.delete_if { |_key, attempt| attempt[:updated_at] < cutoff }
      @transfer_attempts.shift while @transfer_attempts.length > MAX_TRANSFER_ATTEMPTS
    end

    def prune_unmanaged_attempts(dns_config)
      @transfer_attempts.delete_if do |_key, attempt|
        dns_config[attempt[:zone]].nil?
      end
    end

    def monotonic_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def event(zone, status, **attrs)
      attrs.merge(
        name: normalize_zone_name(zone),
        status:
      )
    end

    def normalize_zone_name(zone)
      zone.end_with?('.') ? zone : "#{zone}."
    end

    def event_key(cursor, event, message)
      return Digest::SHA256.hexdigest(cursor) if cursor

      Digest::SHA256.hexdigest(
        [
          $CFG.get(:vpsadmin, :node_id),
          event[:name],
          event[:time],
          event[:status],
          event[:attempt_kind],
          event[:failure_class],
          event[:reason_code],
          event[:primary_addr],
          event[:serial],
          message
        ].join("\0")
      )
    end
  end
end
