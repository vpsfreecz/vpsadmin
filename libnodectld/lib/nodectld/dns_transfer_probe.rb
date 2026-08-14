require 'digest'
require 'fileutils'
require 'json'
require 'libosctl'
require 'securerandom'
require 'nodectld/dns_transfer_probe_worker'
require 'nodectld/dns_transfer_probe_runner'

module NodeCtld
  class DnsTransferProbe
    include OsCtl::Lib::Utils::Log

    RunningProbe = Struct.new(:thread, :unit_name, :cancelled)
    FAST_RETRY_REASON_CODES = %w[
      connection_failed
      not_authoritative
      not_found
      refused
      servfail
      timeout
      tsig_error
    ].freeze
    REASON_TEXT = DnsTransferProbeWorker::REASON_TEXT

    class << self
      attr_accessor :instance
    end

    def initialize(runner: DnsTransferProbeRunner.new)
      self.class.instance = self
      @runner = runner
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
      path_map = probe_paths.to_h do |zone, primary|
        [path_key(zone, primary), [zone, primary]]
      end
      cancel_units = []

      @mutex.synchronize do
        (@schedule.keys - path_map.keys).each { |key| @schedule.delete(key) }
        (@running.keys - path_map.keys).each do |key|
          running = @running.fetch(key)
          next if running.cancelled

          running.cancelled = true
          cancel_units << running.unit_name
        end

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
          running = RunningProbe.new(
            unit_name: unit_name(key),
            cancelled: false
          )
          @runner.prepare(running.unit_name)
          @running[key] = running
          begin
            running.thread = start_probe_thread do
              run_scheduled_probe(key, zone, primary, running)
            end
          rescue ThreadError => e
            @running.delete(key)
            @schedule[key] = now + 5
            @runner.release(running.unit_name)
            log(
              :warn,
              "Unable to start DNS transfer probe thread: #{e.message}"
            )
          end
        end
      end

      cancel_units.each { |name| @runner.cancel(name) }
    end

    def run_scheduled_probe(key, zone, primary, running = nil)
      running ||= RunningProbe.new(unit_name: unit_name(key), cancelled: false)
      return unless current_path?(key, running)

      force_axfr = needs_axfr?(key)
      result = @runner.run(
        probe_job(zone, primary, force_axfr:),
        unit_name: running.unit_name
      )
      return unless current_path?(key, running)

      persistent_key = persistent_path_key(key)
      if result[:status] == 'failed' &&
         %w[invalid_zone protocol_error].include?(result[:reason_code])
        @mutex.synchronize do
          @persistent[persistent_key] = { 'needs_axfr' => true }
          save_persistent_state
        end
      end

      publish(build_event(zone, primary, result))

      @mutex.synchronize do
        if result[:status] == 'success' && result[:attempt_kind] == 'axfr_probe'
          @persistent.delete(persistent_key)
          save_persistent_state
        end

        @schedule[key] ||= Time.now.to_f + next_interval(result)
      end
    rescue DnsTransferProbeRunner::Cancelled
      nil
    rescue DnsTransferProbeRunner::Error => e
      handle_local_failure(key, zone, primary, running, force_axfr, e.message)
    rescue StandardError => e
      log(:warn, "DNS transfer probe #{key} failed with #{e.class}: #{e.message}")
      handle_local_failure(
        key,
        zone,
        primary,
        running,
        force_axfr,
        "Probe coordinator failed with #{e.class}"
      )
    ensure
      @mutex.synchronize do
        @running.delete(key) if @running[key].equal?(running)
      end
      @runner.release(running.unit_name)
    end

    def start_probe_thread(&)
      Thread.new(&)
    end

    def probe_job(zone, primary, force_axfr:)
      {
        'zone_name' => zone.name,
        'primary_addr' => primary.fetch('ip_addr'),
        'source_addr' => zone.probe_source_addr(primary.fetch('ip_addr')),
        'tsig_key' => primary['tsig_key'],
        'loaded_serial' => zone.loaded_serial,
        'force_axfr' => force_axfr,
        'probe_timeout' => probe_timeout,
        'axfr_timeout' => axfr_timeout,
        'axfr_max_bytes' => axfr_max_bytes
      }
    end

    def build_event(zone, primary, result)
      time = Time.now.to_i
      event = result.merge(
        name: zone.name,
        dns_server_zone_id: zone.id,
        dns_zone_transfer_id: primary.fetch('id'),
        configuration_generation: zone.primary_transfer_generation,
        time:,
        primary_addr: primary.fetch('ip_addr'),
        source_cursor: nil,
        raw_message: nil
      )
      event[:event_key] = Digest::SHA256.hexdigest(
        [
          $CFG.get(:vpsadmin, :node_id), zone.id, primary.fetch('id'),
          zone.primary_transfer_generation, time, event[:status],
          event[:attempt_kind], event[:failure_class], event[:reason_code],
          event[:primary_serial], event[:secondary_serial], event[:message]
        ].join("\0")
      )
      event
    end

    def local_failure_result(force_axfr, message)
      {
        status: 'failed',
        attempt_kind: force_axfr ? 'axfr_probe' : 'ixfr_probe',
        failure_class: 'local',
        reason_code: 'probe_limit',
        reason: REASON_TEXT.fetch('probe_limit'),
        message: message.to_s.byteslice(
          0,
          DnsTransferProbeWorker::MAX_DIAGNOSTIC_BYTES
        ).to_s.scrub('?')
      }
    end

    def handle_local_failure(key, zone, primary, running, force_axfr, message)
      return unless current_path?(key, running)

      result = local_failure_result(force_axfr, message)
      begin
        publish(build_event(zone, primary, result))
      rescue StandardError => e
        log(:warn, "Unable to publish DNS transfer probe failure: #{e.message}")
      ensure
        @mutex.synchronize do
          @schedule[key] ||= Time.now.to_f + next_interval(result)
        end
      end
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
                       zone.type == 'secondary_type' &&
                       zone.primary_transfer_generation

        zone.user_primaries.map { |primary| [zone, primary] }
      end
    end

    def current_path?(key, running)
      return false if running&.cancelled

      probe_paths.any? do |zone, primary|
        path_key(zone, primary) == key
      end
    end

    def path_key(zone, primary)
      "#{zone.id}:#{primary.fetch('id')}:#{zone.primary_transfer_generation}"
    end

    def persistent_path_key(key)
      key.split(':', 3).first(2).join(':')
    end

    def initial_delay(key)
      1 + (Digest::SHA256.hexdigest(key)[0, 8].to_i(16) % 60)
    end

    def unit_name(key)
      digest = Digest::SHA256.hexdigest(key)[0, 16]
      "vpsadmin-dns-transfer-probe-#{digest}-#{SecureRandom.hex(4)}"
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
