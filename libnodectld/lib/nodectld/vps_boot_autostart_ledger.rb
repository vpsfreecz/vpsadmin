# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'libosctl'

module NodeCtld
  # Only the node boot hook creates this record. A daemon restart must never
  # replace missing evidence with a new cohort or rearm a terminal obligation.
  class VpsBootAutostartLedger
    include OsCtl::Lib::Utils::Log

    PATH = '/run/nodectl/boot-autostart.json'
    FAILURE_PATH = '/run/nodectl/boot-autostart.failed.json'
    BOOT_MARKER = '/run/booted-system/etc/nodectl/boot-autostart-version'
    DEADLINE = 300
    RETIRE_REASONS = %w[deleted assigned_elsewhere inactive autostart_disabled pool_changed].freeze
    FAILURE_REASONS = %w[enrollment_timeout inventory_invalid].freeze

    class Invalid < StandardError; end

    attr_reader :record, :failure_reason

    def initialize(path: PATH, boot_id: File.read('/proc/sys/kernel/random/boot_id').strip,
                   marker: BOOT_MARKER, failure_path: "#{path.delete_suffix('.json')}.failed.json")
      @path = path
      @failure_path = failure_path
      @boot_id = boot_id
      @record = nil
      load_record(marker)
    end

    def phase
      if @record
        @record.fetch('phase')
      else
        (@failure_reason == 'not_enrolled' ? 'awaiting_reboot' : 'unavailable')
      end
    end

    def capture(vpses, now:, clock: -> { now })
      raise Invalid unless phase == 'enrolling' && timestamp?(now) && now < DEADLINE

      rows = inventory(vpses)
      replace(@record.merge(
                'phase' => 'active',
                'captured_at_boottime_seconds' => now,
                'obligations' => rows.map do |row|
                  row.merge('pool' => pool(row.fetch('pool_fs')), 'state' => 'pending', 'reason' => nil)
                end
              ), capture_clock: clock)
    end

    def enrollment_failed(reason)
      raise Invalid unless FAILURE_REASONS.include?(reason)

      replace(@record.merge('phase' => 'unavailable', 'failure_reason' => reason,
                            'captured_at_boottime_seconds' => nil, 'obligations' => []))
    end

    def pending
      obligations.select { |row| row.fetch('state') == 'pending' }
    end

    def obligations
      @record ? @record.fetch('obligations') : []
    end

    def transition(fulfilled: [], retired: {})
      rows = obligations.map do |row|
        next row unless row.fetch('state') == 'pending'

        id = row.fetch('id')
        if fulfilled.include?(id)
          row.merge('state' => 'fulfilled', 'reason' => 'running')
        elsif retired.has_key?(id)
          reason = retired.fetch(id)
          raise Invalid unless RETIRE_REASONS.include?(reason)

          row.merge('state' => 'retired', 'reason' => reason)
        else
          row
        end
      end
      return true if rows == obligations

      replace(@record.merge('obligations' => rows))
    end

    def inventory(response)
      raise Invalid unless response.is_a?(Hash) && response['schema_version'].is_a?(Integer) &&
                           response['schema_version'] == 1 && response['vpses'].is_a?(Array)

      rows = response.fetch('vpses')
      rows.each do |row|
        raise Invalid unless row.is_a?(Hash) && positive_id?(row['id']) && pool_fs?(row['pool_fs'])
      end
      raise Invalid unless rows.map { |row| row.fetch('id') }.uniq.length == rows.length

      rows.sort_by { |row| row.fetch('id') }.map { |row| row.slice('id', 'pool_fs') }
    end

    def pool(value)
      value.split('/', 2).first
    end

    def pool_fs?(value)
      value.is_a?(String) && value.match?(%r{\A[A-Za-z0-9][A-Za-z0-9_.:-]*(?:/[A-Za-z0-9_.:-]+)*\z}) &&
        !value.split('/').intersect?(%w[. ..])
    end

    def name?(value)
      value.is_a?(String) && /\A[a-zA-Z0-9][a-zA-Z0-9_.:-]*\z/.match?(value)
    end

    def positive_id?(value)
      value.is_a?(Integer) && value > 0
    end

    def timestamp?(value)
      value.is_a?(Numeric) && value.finite? && value >= 0
    end

    protected

    def load_record(marker)
      if failure_present?
        @failure_reason = 'persistence_failed'
        return
      end

      value = JSON.parse(File.read(@path))
      validate(value)
      if value.fetch('boot_id') != @boot_id
        @failure_reason = 'boot_id_mismatch'
        return
      end
      @record = value
      @failure_reason = value['failure_reason']
    rescue Errno::ENOENT
      @failure_reason = File.exist?(marker) ? 'state_missing' : 'not_enrolled'
    rescue JSON::ParserError, Invalid, SystemCallError, IOError
      @failure_reason = 'state_invalid'
    end

    def validate(value)
      required = %w[schema_version boot_id phase capture_deadline_boottime_seconds failure_reason captured_at_boottime_seconds obligations]
      raise Invalid unless value.is_a?(Hash) && required.all? { |key| value.has_key?(key) } &&
                           value['schema_version'].is_a?(Integer) && value['schema_version'] == 1 &&
                           value['boot_id'].is_a?(String) && !value['boot_id'].empty? &&
                           value['capture_deadline_boottime_seconds'] == DEADLINE &&
                           value['obligations'].is_a?(Array)

      case value['phase']
      when 'enrolling'
        raise Invalid unless value['captured_at_boottime_seconds'].nil? &&
                             value['failure_reason'].nil? && value['obligations'].empty?
      when 'unavailable'
        raise Invalid unless FAILURE_REASONS.include?(value['failure_reason']) &&
                             value['captured_at_boottime_seconds'].nil? && value['obligations'].empty?
      when 'active'
        captured = value['captured_at_boottime_seconds']
        raise Invalid unless timestamp?(captured) && captured < DEADLINE && value['failure_reason'].nil?

        validate_obligations(value['obligations'])
      else
        raise Invalid
      end
    end

    def validate_obligations(rows)
      rows.each do |row|
        raise Invalid unless row.is_a?(Hash) && row.has_key?('reason') && positive_id?(row['id']) && pool_fs?(row['pool_fs']) &&
                             row['pool'] == pool(row['pool_fs'])

        valid = case row['state']
                when 'pending' then row['reason'].nil?
                when 'fulfilled' then row['reason'] == 'running'
                when 'retired' then RETIRE_REASONS.include?(row['reason'])
                else false
                end
        raise Invalid unless valid
      end
      raise Invalid unless rows.map { |row| row.fetch('id') }.uniq.length == rows.length
    end

    def replace(value, capture_clock: nil)
      return false if @failure_reason == 'persistence_failed'

      temporary = "#{@path}.#{Process.pid}.#{SecureRandom.hex(6)}"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.generate(value))
        file.flush
        file.fsync
      end
      if capture_clock && capture_clock.call >= DEADLINE
        return enrollment_failed('enrollment_timeout')
      end

      File.rename(temporary, @path)
      if capture_clock && capture_clock.call >= DEADLINE
        return enrollment_failed('enrollment_timeout')
      end

      @record = value
      @failure_reason = value['failure_reason']
      true
    rescue SystemCallError, IOError
      persistence_failed
      false
    ensure
      cleanup_temporary(temporary) if temporary
    end

    def cleanup_temporary(path)
      File.unlink(path)
    rescue Errno::ENOENT
      nil
    rescue SystemCallError, IOError
      persistence_failed
    end

    def persistence_failed
      @failure_reason = 'persistence_failed'
      return if failure_present?

      begin
        File.rename(@path, @failure_path)
        return
      rescue SystemCallError, IOError
        # Keep the old record as failure evidence when possible. If the
        # directory rejects rename, try a small independent failure sentinel.
      end

      begin
        File.open(@failure_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.generate(schema_version: 1, boot_id: @boot_id, reason: 'persistence_failed'))
          file.flush
          file.fsync
        end
        return
      rescue SystemCallError, IOError
        # If no sentinel can be saved, invalidate the stale healthy predecessor.
      end

      begin
        File.unlink(@path)
      rescue SystemCallError, IOError
        log(:error, :vps_boot_autostart, 'Unable to preserve persistence failure across restart')
      end
    end

    def failure_present?
      File.lstat(@failure_path)
      true
    rescue Errno::ENOENT
      false
    rescue SystemCallError
      # An inaccessible sentinel cannot establish healthy evidence either.
      true
    end
  end
end
