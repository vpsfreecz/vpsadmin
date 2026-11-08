require 'digest'
require_relative 'base'

module VpsAdmin::Supervisor
  class Node::DnsTransferLog < Node::Base
    SUPPORTED_STATUSES = %w[success failed].freeze
    SUPPORTED_ATTEMPT_KINDS = %w[
      transfer refresh notify load ixfr_probe axfr_probe
    ].freeze
    SUPPORTED_FAILURE_CLASSES = %w[primary network local lifecycle unknown].freeze
    ACTIONABLE_FAILURE_CLASSES = %w[primary network].freeze
    PROBE_ATTEMPT_KINDS = %w[ixfr_probe axfr_probe].freeze
    FULL_RECOVERY_ATTEMPT_KINDS = %w[transfer axfr_probe].freeze
    CHEAP_RECOVERY_REASON_CODES = %w[
      refused not_authoritative not_found servfail timeout connection_failed
      tsig_error stale
    ].freeze

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('dns_transfer_logs'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'dns_transfer_logs')

      queue.subscribe do |_delivery_info, _properties, payload|
        JSON.parse(payload).fetch('events').each do |event|
          save_event(event)
        end
      end
    end

    protected

    def save_event(event)
      return unless valid_envelope?(event)

      dns_server_zone = find_dns_server_zone(event)
      return if dns_server_zone.nil?

      event_at = Time.at(event.fetch('time'))
      event_key = event['event_key'] || event_key(event)

      dns_server_zone.with_lock do
        dns_server_zone.reload
        return unless ::DnsServerZone.existing.where(id: dns_server_zone.id).exists?

        dns_zone_transfer = current_dns_zone_transfer(
          dns_server_zone,
          event,
          event_at
        )

        # An event that names a primary path but no longer belongs to the
        # current generation is neither current state nor user-visible history.
        return if event['dns_zone_transfer_id'] && dns_zone_transfer.nil?

        state = find_primary_transfer_state(dns_server_zone, dns_zone_transfer)
        state_event_current = state.nil? ||
                              later_than_primary_transfer_state?(state, event, event_at, event_key)
        return if !state_event_current && PROBE_ATTEMPT_KINDS.include?(event['attempt_kind'])

        persist = persist_event?(event, state, event_at)
        log =
          if persist
            save_log(
              dns_server_zone,
              dns_zone_transfer,
              event,
              event_at,
              event_key
            )
          end

        update_latest_transfer(dns_server_zone, log) if log&.attempt_transfer?
        if state_event_current
          update_primary_transfer_state(
            dns_server_zone,
            dns_zone_transfer,
            state,
            event,
            event_at,
            event_key,
            log
          )
        end
      end
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def valid_envelope?(event)
      return false unless event['dns_server_zone_id']
      if event['dns_zone_transfer_id'] && event['configuration_generation'].blank?
        return false
      end
      return false unless SUPPORTED_STATUSES.include?(event['status'])
      return false unless SUPPORTED_ATTEMPT_KINDS.include?(event['attempt_kind'])

      if event['status'] == 'failed'
        SUPPORTED_FAILURE_CLASSES.include?(event['failure_class'])
      else
        event['failure_class'].nil?
      end
    end

    def find_dns_server_zone(event)
      ::DnsServerZone
        .existing
        .joins(:dns_zone, :dns_server)
        .find_by(
          id: event.fetch('dns_server_zone_id'),
          dns_zones: { name: event.fetch('name') },
          dns_servers: { node_id: node.id }
        )
    end

    def current_dns_zone_transfer(dns_server_zone, event, event_at)
      transfer_id = event['dns_zone_transfer_id']
      return if transfer_id.nil?

      dns_zone = dns_server_zone.dns_zone
      return unless dns_zone.enabled? && dns_zone.external_source?
      return unless event['configuration_generation'] ==
                    dns_server_zone.primary_transfer_configuration_generation

      tracking_started_at = dns_zone.primary_transfer_tracking_started_at
      return if tracking_started_at.nil?

      transfer =
        dns_zone
        .dns_zone_transfers
        .existing
        .primary_type
        .lock
        .find_by(id: transfer_id)
      return if transfer.nil?

      boundary = [tracking_started_at, dns_server_zone.created_at, transfer.created_at].max
      event_at > boundary ? transfer : nil
    end

    def find_primary_transfer_state(dns_server_zone, dns_zone_transfer)
      return if dns_zone_transfer.nil?

      ::DnsServerZonePrimaryTransferState.find_by(
        dns_server_zone:,
        dns_zone_transfer:
      )
    end

    def persist_event?(event, state, event_at)
      return true unless PROBE_ATTEMPT_KINDS.include?(event['attempt_kind'])
      if event['status'] == 'failed' &&
         !ACTIONABLE_FAILURE_CLASSES.include?(event['failure_class'])
        return probe_diagnostic_changed?(state, event)
      end
      return true unless ACTIONABLE_FAILURE_CLASSES.include?(event['failure_class']) ||
                         event['status'] == 'success'
      return event['status'] == 'failed' if state.nil?
      return true if state.status != event['status']

      if event['status'] == 'failed'
        return true if state.failure_class != event['failure_class'] ||
                       state.reason_code != event['reason_code']

        becomes_eligible = state.alert_eligible_at.nil? &&
                           continuously_failed?(state, event_at) &&
                           event_at >= state.failed_since + state.alert_delay
        return becomes_eligible
      end

      false
    end

    def probe_diagnostic_changed?(state, event)
      return true if state.nil? || state.last_transfer_log.nil?

      log = state.last_transfer_log
      log.failure_class != event['failure_class'] ||
        log.reason_code != event['reason_code'] ||
        log.message != event['message']
    end

    def save_log(dns_server_zone, dns_zone_transfer, event, event_at, event_key)
      log = ::DnsServerZoneTransferLog.find_or_initialize_by(event_key:)
      return log if log.persisted?

      log.assign_attributes(
        dns_server_zone:,
        dns_zone_transfer:,
        event_at:,
        status: event.fetch('status'),
        attempt_kind: event.fetch('attempt_kind'),
        failure_class: event['failure_class'],
        reason_code: event['reason_code'],
        reason: event['reason'],
        primary_addr: event['primary_addr'],
        serial: event['serial'],
        primary_serial: event['primary_serial'],
        secondary_serial: event['secondary_serial'],
        message: event['message'],
        raw_message: event['raw_message'],
        source_cursor: event['source_cursor']
      )
      log.save!
      log
    end

    def update_latest_transfer(dns_server_zone, log)
      if log.failed? &&
         (log.dns_zone_transfer.nil? || !ACTIONABLE_FAILURE_CLASSES.include?(log.failure_class))
        return
      end
      return unless later_than_latest_transfer?(dns_server_zone, log)

      dns_server_zone.update!(
        last_transfer_log: log,
        last_transfer_at: log.event_at,
        last_transfer_status: log.status,
        last_transfer_reason_code: log.failed? ? log.reason_code : nil,
        last_transfer_reason: log.failed? ? log.reason : nil,
        last_transfer_primary_addr: log.primary_addr,
        last_transfer_serial: log.serial
      )
    end

    def update_primary_transfer_state(
      dns_server_zone,
      dns_zone_transfer,
      state,
      event,
      event_at,
      event_key,
      log
    )
      return if dns_zone_transfer.nil?

      state ||= ::DnsServerZonePrimaryTransferState.new(
        dns_server_zone:,
        dns_zone_transfer:
      )

      if event['status'] == 'failed' && ACTIONABLE_FAILURE_CLASSES.include?(event['failure_class'])
        update_failed_primary_transfer_state(state, event, event_at, event_key, log)
      elsif event['status'] == 'success' &&
            %w[transfer ixfr_probe axfr_probe].include?(event['attempt_kind'])
        update_successful_primary_transfer_state(state, event, event_at, event_key, log)
      elsif state.persisted?
        update_observation_watermark(state, event, event_at, event_key, log)
      elsif PROBE_ATTEMPT_KINDS.include?(event['attempt_kind'])
        state.assign_attributes(
          status: :unknown,
          failure_class: nil,
          failed_since: nil,
          last_failure_at: nil,
          alert_eligible_at: nil,
          reason_code: nil,
          reason: nil
        )
        apply_observation(state, event, event_at, event_key, log)
      end
    end

    def update_failed_primary_transfer_state(state, event, event_at, event_key, log)
      continuous = state.persisted? && state.failed? &&
                   state.failure_class == event['failure_class'] &&
                   continuously_failed?(state, event_at)
      failed_since = continuous ? state.failed_since : event_at
      delay = event['failure_class'] == 'network' ? 24.hours : 30.minutes
      alert_eligible_at =
        if continuous && event_at >= failed_since + delay
          failed_since + delay
        end

      state.assign_attributes(
        status: :failed,
        failure_class: event.fetch('failure_class'),
        failed_since:,
        last_failure_at: event_at,
        alert_eligible_at:,
        reason_observed_at: event_at,
        reason_code: event['reason_code'],
        reason: event['reason'],
        primary_serial: event['primary_serial'],
        secondary_serial: event['secondary_serial']
      )
      apply_observation(state, event, event_at, event_key, log)
    end

    def update_successful_primary_transfer_state(state, event, event_at, event_key, log)
      if state.persisted? && state.failed? && !success_recovers?(state, event)
        update_observation_watermark(state, event, event_at, event_key, log)
        return
      end

      state.assign_attributes(
        status: :success,
        failure_class: nil,
        failed_since: nil,
        last_failure_at: nil,
        last_success_at: event_at,
        alert_eligible_at: nil,
        reason_observed_at: nil,
        reason_code: nil,
        reason: nil,
        primary_serial: event['primary_serial'] || event['serial'] || state.primary_serial,
        secondary_serial: event['secondary_serial'] || state.secondary_serial
      )
      apply_observation(state, event, event_at, event_key, log)
    end

    def success_recovers?(state, event)
      return true if FULL_RECOVERY_ATTEMPT_KINDS.include?(event['attempt_kind'])
      return false unless event['attempt_kind'] == 'ixfr_probe'

      CHEAP_RECOVERY_REASON_CODES.include?(state.reason_code)
    end

    def update_observation_watermark(state, event, event_at, event_key, log)
      apply_observation(state, event, event_at, event_key, log)
    end

    def apply_observation(state, event, event_at, event_key, log)
      state.assign_attributes(
        last_transfer_log: log || state.last_transfer_log,
        configuration_generation: event.fetch('configuration_generation'),
        last_event_key: event_key,
        last_attempt_at: event_at,
        last_attempt_kind: event.fetch('attempt_kind')
      )
      state.save!
    end

    def continuously_failed?(state, event_at)
      gap =
        if ::DnsServerZonePrimaryTransferState::SLOW_PROBE_REASON_CODES.include?(
          state.reason_code
        )
          ::DnsServerZonePrimaryTransferState::SLOW_FAILURE_CONTINUITY_GAP
        else
          ::DnsServerZonePrimaryTransferState::FAILURE_CONTINUITY_GAP
        end

      state.last_failure_at &&
        event_at <= state.last_failure_at + gap
    end

    def later_than_latest_transfer?(dns_server_zone, log)
      return true if dns_server_zone.last_transfer_at.nil?
      return true if log.event_at > dns_server_zone.last_transfer_at
      return false if log.event_at < dns_server_zone.last_transfer_at

      log.id > dns_server_zone.last_transfer_log_id.to_i
    end

    def later_than_primary_transfer_state?(state, event, event_at, event_key)
      return true if event_at > state.last_attempt_at
      return false if event_at < state.last_attempt_at
      return true if event['status'] == 'success' && state.failed?
      return false if event['status'] == 'failed' && !state.failed?

      event_key > state.last_event_key
    end

    def event_key(event)
      Digest::SHA256.hexdigest(
        [
          node.id,
          event['dns_server_zone_id'],
          event['dns_zone_transfer_id'],
          event['configuration_generation'],
          event['source_cursor'],
          event['name'],
          event['time'],
          event['status'],
          event['attempt_kind'],
          event['failure_class'],
          event['reason_code'],
          event['primary_addr'],
          event['serial'],
          event['primary_serial'],
          event['secondary_serial'],
          event['message']
        ].join("\0")
      )
    end
  end
end
