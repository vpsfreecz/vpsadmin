require 'digest'
require 'fileutils'
require 'json'
require 'libosctl'
require 'shellwords'
require 'time'

module NodeCtld
  class DnsTransferLog
    include OsCtl::Lib::Utils::Log

    REASON_TEXT = {
      'invalid_zone' => 'The transferred zone contains errors and was rejected',
      'refused' => 'The primary DNS server refused the transfer',
      'not_authoritative' => 'The primary DNS server is not authoritative for the zone',
      'not_found' => 'The primary DNS server does not know the zone',
      'servfail' => 'The primary DNS server returned a server failure',
      'timeout' => 'The primary DNS server did not respond in time',
      'connection_failed' => 'The primary DNS server could not be reached',
      'tsig_error' => 'The transfer failed TSIG authentication',
      'unknown' => 'The transfer failed'
    }.freeze

    attr_reader :cursor_file

    def initialize
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
      @cursor_file = $CFG.get(:dns_server, :transfer_log_cursor_file)
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
      event = parse_message(message)

      if event && DnsConfig.instance[event[:name]]
        event.update(
          time: journal_time(entry),
          message: event[:message] || message,
          raw_message: message,
          source_cursor: cursor,
          event_key: event_key(cursor, event, message)
        )

        publish(event)
      end

      save_cursor(cursor) if cursor
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

    def parse_message(message)
      parse_transfer_completed(message) ||
        parse_transfer_status(message) ||
        parse_transfer_failed(message) ||
        parse_refresh_failed(message) ||
        parse_zone_load_failed(message) ||
        parse_transfer_started(message)
    end

    def parse_transfer_completed(message)
      return unless %r{transfer of '([^']+)/IN' from ([^#\s]+)#\d+: Transfer completed: .*serial (\d+)} =~ message

      event(
        Regexp.last_match(1),
        'success',
        primary_addr: Regexp.last_match(2),
        serial: Regexp.last_match(3).to_i,
        message: 'Transfer completed successfully'
      )
    end

    def parse_transfer_status(message)
      return unless %r{transfer of '([^']+)/IN' from ([^#\s]+)#\d+: Transfer status: (.+)\z} =~ message

      zone = Regexp.last_match(1)
      primary_addr = Regexp.last_match(2)
      status = Regexp.last_match(3).strip

      return if status.casecmp('success') == 0

      failed_event(zone, primary_addr, status)
    end

    def parse_transfer_failed(message)
      return unless %r{transfer of '([^']+)/IN' from ([^#\s]+)#\d+: .*failed.*: (.+)\z} =~ message

      failed_event(Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3))
    end

    def parse_refresh_failed(message)
      return unless %r{zone ([^/]+)/IN: refresh: failure trying primary ([^#\s]+)#\d+.*: (.+)\z} =~ message

      failed_event(Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3))
    end

    def parse_zone_load_failed(message)
      return unless %r{zone ([^/]+)/IN: (?:loading from .* failed|not loaded due to errors|.+has no address records)} =~ message

      event(
        Regexp.last_match(1),
        'failed',
        reason_code: 'invalid_zone',
        reason: REASON_TEXT.fetch('invalid_zone'),
        message:
      )
    end

    def parse_transfer_started(message)
      return unless %r{zone ([^/]+)/IN: Transfer started} =~ message

      event(Regexp.last_match(1), 'started', message: 'Transfer started')
    end

    def failed_event(zone, primary_addr, reason)
      reason_code = reason_code(reason)

      event(
        zone,
        'failed',
        primary_addr:,
        reason_code:,
        reason: REASON_TEXT.fetch(reason_code),
        message: reason
      )
    end

    def reason_code(reason)
      normalized = reason.to_s.downcase

      if normalized.include?('bad zone') || normalized.include?('not loaded due to errors') ||
         normalized.include?('has no address records') || normalized.include?('invalid')
        'invalid_zone'
      elsif normalized.include?('connection refused') || normalized.include?('network unreachable') ||
            normalized.include?('host unreachable') || normalized.include?('no route to host') ||
            normalized.include?('connection reset') || normalized.include?('connection failed')
        'connection_failed'
      elsif normalized.include?('refused')
        'refused'
      elsif normalized.include?('notauth') || normalized.include?('not authoritative') ||
            normalized.include?('not authoritative for')
        'not_authoritative'
      elsif normalized.include?('nxdomain') || normalized.include?('not found') ||
            normalized.include?('does not exist')
        'not_found'
      elsif normalized.include?('servfail') || normalized.include?('server failure')
        'servfail'
      elsif normalized.include?('timed out') || normalized.include?('timeout')
        'timeout'
      elsif normalized.include?('tsig') || normalized.include?('badkey') ||
            normalized.include?('badsig') || normalized.include?('badtime')
        'tsig_error'
      else
        'unknown'
      end
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
          event[:reason_code],
          event[:primary_addr],
          event[:serial],
          message
        ].join("\0")
      )
    end
  end
end
