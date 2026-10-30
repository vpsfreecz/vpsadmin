require 'digest'

# Decisions and chain preparation share the VPS row lock. The normal resource
# lock still protects physical operations; a busy resource defers this decision.
class IncidentEscalation
  DAY = 24 * 60 * 60
  STATUSES = %w[clear near_limit warning stop_threshold].freeze
  SETTINGS = %w[incident_warning_limit_override incident_stop_limit_override incident_enforcement_enabled].freeze
  SUMMARY_FIELDS = %i[
    incident_policy incident_policy_label incident_count_7d incident_count_30d
    incident_warning_limit_override incident_stop_limit_override incident_warning_limit incident_stop_limit
    incident_enforcement_enabled incident_mode incident_stop_enforced incident_status
    incident_last_incident_at incident_last_warning_at incident_last_stop_at
    incident_next_stop_allowed_at incident_action_state incident_action_chain_id incident_accounting_since
  ].freeze

  class InvalidConfiguration < StandardError; end

  def self.config(values = nil, incident_type: 'oomd')
    values ||= SysConfig.where(category: rule(incident_type).category).to_h { |row| [row.name, row.value] }
    warning = values.fetch('warning_limit', 5)
    stop = values.fetch('stop_limit', 10)
    mode = values.fetch('mode', 'observe')
    unless %w[observe notify enforce].include?(mode) && warning.is_a?(Integer) && warning > 0 &&
           stop.is_a?(Integer) && stop >= warning
      raise InvalidConfiguration, VpsAdmin::API::I18n.t('errors.incident_escalation.invalid_configuration')
    end

    { mode:, warning:, stop: }
  end

  Rule = Struct.new(:key, :labels, :category, :qualification, :warning_template, :stopped_template) do
    def reports(scope = IncidentReport.all)
      qualification.call(scope)
    end

    def label(language = :en)
      labels.fetch(language.to_s, labels.fetch('en'))
    end
  end

  RULES = {
    'oomd' => Rule.new(
      key: 'oomd', labels: { 'en' => 'VPS memory-pressure incidents', 'cs' => 'Incidenty přetížení paměti VPS' },
      category: 'incident_policy_oomd', warning_template: :vps_memory_pressure_warning,
      stopped_template: :vps_memory_pressure_stopped,
      qualification: lambda { |scope|
        scope.where(codename: 'oomd', source_kind: 'node_vps_event', source_action: %w[restart stop])
        .where.not(source_key: nil).where.not(source_node_id: nil)
      }
    )
  }.freeze

  def self.rule(type = 'oomd')
    RULES.fetch(type.to_s) { raise ArgumentError, 'Invalid incident policy' }
  end

  def self.qualified_reports
    RULES.values.map(&:reports).reduce { |scope, other| scope.or(other) }
  end

  def self.mixed_settings?(attributes)
    keys = attributes.keys.map(&:to_s)
    keys.intersect?(SETTINGS + ['incident_policy']) && (keys - SETTINGS - ['incident_policy']).any?
  end

  def self.serialized(vps, &block)
    Vps.transaction do
      SysConfig.where(category: RULES.values.map(&:category)).order(:id).lock.load
      vps.with_lock(&block)
    end
  end

  def self.update_settings!(vps, attributes)
    attrs = attributes.stringify_keys
    if mixed_settings?(attrs) || !attrs.has_key?('incident_policy') || !attrs.keys.intersect?(SETTINGS)
      vps.errors.add(:base, VpsAdmin::API::I18n.t('errors.incident_escalation.separate_update'))
      raise ActiveRecord::RecordInvalid, vps
    end
    selected = rule(attrs.fetch('incident_policy'))
    if attrs.has_key?('incident_enforcement_enabled') && ![true, false].include?(attrs['incident_enforcement_enabled'])
      vps.errors.add(:incident_enforcement_enabled, 'must be true or false')
      raise ActiveRecord::RecordInvalid, vps
    end
    serialized(vps) do
      policy = VpsIncidentPolicy.find_or_initialize_by(vps:, incident_type: selected.key)
      %w[warning_limit_override stop_limit_override].each do |field|
        key = "incident_#{field}"
        policy.public_send("#{field}=", attrs[key]) if attrs.has_key?(key)
      end
      policy.save!
      vps.update!(incident_enforcement_enabled: attrs['incident_enforcement_enabled']) if attrs.has_key?('incident_enforcement_enabled')
      vps.incident_summary = nil
    end
  end

  def self.ingest!(vps, incident_type:, attributes:, source_node: nil, now: Time.now.utc)
    selected = rule(incident_type)
    serialized(vps) do
      return if source_node && vps.node_id != source_node.id
      return if attributes[:source_key] && IncidentReport.exists?(source_key: attributes[:source_key])

      incident = IncidentReport.create!(attributes.merge(user: vps.user, vps:))
      yield incident if block_given?
      policy = new(vps, incident_type: selected.key, now:)
      policy.reconcile_transfer!
      policy.reconcile_actions!
      policy.decide!(incident)
    end
    process!(vps, now:)
  end

  def self.process!(vps, now: Time.now.utc)
    serialized(vps) do
      policy = new(vps, now:)
      policy.reconcile_transfer!
      policy.reconcile_actions!
      RULES.each_key { |type| new(vps, incident_type: type, now:).dispatch_actions! }
      policy.queue_incident_reports!
    end
  end

  def initialize(vps, incident_type: 'oomd', now: Time.now.utc)
    @vps = vps
    @rule = self.class.rule(incident_type)
    @vps.incident_summary = nil
    @now = now
  end

  def config
    @config ||= self.class.config(incident_type: @rule.key)
  end

  # Decisions use persisted state, independent of a cached display summary.
  def counts
    q = @rule.reports.where(vps_id: @vps.id, user_id: @vps.user_id)
             .where('detected_at <= ? AND detected_at > ?', @now, @now - (30 * DAY))
    q = q.where('detected_at >= ?', @vps[:incident_accounting_since]) if @vps[:incident_accounting_since]
    [q.where('detected_at > ?', @now - (7 * DAY)).count, q.count]
  end

  def policy
    @policy ||= VpsIncidentPolicy.find_or_initialize_by(vps: @vps, incident_type: @rule.key)
  end

  def limits
    warning = policy.warning_limit_override || config[:warning]
    stop = policy.stop_limit_override || config[:stop]
    unless warning.is_a?(Integer) && warning > 0 && stop.is_a?(Integer) && stop >= warning
      raise InvalidConfiguration, VpsAdmin::API::I18n.t('errors.incident_escalation.invalid_configuration')
    end

    [warning, stop]
  end

  def stop_enforced?
    config[:mode] == 'enforce' && @vps.incident_enforcement_enabled
  end

  def applicable?(action)
    action.user_id == @vps.user_id && action.accounting_since == @vps[:incident_accounting_since] &&
      !@vps.incident_owner_transfer_chain_id
  end

  def timely?(incident)
    incident.detected_at.between?(@now - DAY, @now) &&
      (!@vps[:incident_accounting_since] || incident.detected_at >= @vps[:incident_accounting_since])
  end

  def stop_due?(incident, count30)
    return false unless stop_enforced? && count30 >= limits.last
    return true unless @vps[:incident_last_stop_at]

    incident.detected_at > @vps[:incident_last_stop_at] && incident.detected_at >= @vps[:incident_last_stop_at] + DAY
  end

  def warning_due?(count7)
    config[:mode] != 'observe' && count7 >= limits.first &&
      (!policy.last_warning_at || policy.last_warning_at <= @now - (7 * DAY))
  end

  def decide!(incident)
    return unless @rule.reports.where(id: incident.id).exists? && timely?(incident) && !@vps.incident_owner_transfer_chain_id
    return if @vps.vps_incident_actions.outstanding_stops.exists?

    count7, count30 = counts
    limits

    kind = if stop_due?(incident, count30)
             'stop'
           elsif warning_due?(count7)
             'warning'
           end
    return unless kind
    return if kind == 'warning' && @vps.vps_incident_actions.where(incident_type: @rule.key, kind: 'warning', state: %w[pending queued failed]).exists?

    @vps.vps_incident_actions.where(incident_type: @rule.key, kind: 'warning', state: %w[pending failed]).update_all(state: 'suppressed', mail_state: 'suppressed') if kind == 'stop'

    @vps.vps_incident_actions.create!(
      user_id: @vps.user_id, incident_report: incident, incident_type: @rule.key, accounting_since: @vps[:incident_accounting_since],
      kind:, incident_count_7d: count7, incident_count_30d: count30,
      repeated_stop: !!(@vps[:incident_last_stop_at] && (!@vps[:incident_accounting_since] || @vps[:incident_last_stop_at] >= @vps[:incident_accounting_since]))
    )
  rescue InvalidConfiguration => e
    warn e.message
  end

  # Confirmations bypass callbacks. Keep the marker until the complete transfer
  # succeeds, then use its physical Chown timestamp as the new accounting epoch.
  def reconcile_transfer!
    return unless @vps.incident_owner_transfer_chain_id

    chain = TransactionChain.find(@vps.incident_owner_transfer_chain_id)
    if chain.done?
      transaction = chain.transactions.find_by(handle: Transactions::Vps::Chown.t_type, status: [1, 2], done: 1)
      return unless transaction&.finished_at

      @vps.update_columns(incident_accounting_since: transaction.finished_at, incident_owner_transfer_chain_id: nil)
      @vps.vps_incident_policies.update_all(last_warning_at: nil)
    elsif chain.failed?
      @vps.update_columns(incident_owner_transfer_chain_id: nil)
    end
  end

  def reconcile_actions!
    @vps.vps_incident_actions.where.not(state: 'suppressed').where.not(state: 'completed', mail_state: %w[sent suppressed]).find_each do |action|
      if action.kind == 'stop' && action.transaction_chain_id && %w[queued failed uncertain].include?(action.state)
        chain = action.transaction_chain
        transaction = chain.transactions.find_by(handle: Transactions::Vps::Stop.t_type)
        if chain.done? && transaction&.done == 'done' && [1, 2].include?(transaction.status) && transaction.finished_at
          action.update!(state: 'completed', completed_at: transaction.finished_at, error: nil)
          @vps.update_columns(incident_last_stop_at: [@vps[:incident_last_stop_at], transaction.finished_at].compact.max)
        elsif %w[failed fatal resolved done].include?(chain.state)
          action.update!(state: chain.failed? ? 'failed' : 'uncertain', error: 'Stop outcome requires operator reconciliation')
        end
      end
      next unless action.mail_state == 'queued'

      transaction = action.mail_log&.mail_transaction
      if transaction&.done == 'done'
        action.update!(mail_state: [1, 2].include?(transaction.status) ? 'sent' : 'failed', retry_after: @now + (5 * 60))
        action.update!(state: action.mail_state == 'sent' ? 'completed' : 'failed') if action.kind == 'warning'
      elsif action.mail_chain && %w[failed fatal resolved].include?(action.mail_chain.state)
        action.update!(mail_state: 'uncertain', error: 'Mail outcome requires operator reconciliation')
      end
    end
  end

  def queue_incident_reports!
    IncidentReport.where(vps_id: @vps.id, notification_processed_at: nil).where.not(source_key: nil).find_each do |incident|
      # A delayed old-owner event is retained for audit, not mailed to a new owner.
      next unless incident.user_id == @vps.user_id
      next if incident.detected_at > incident.created_at
      next if @vps[:incident_accounting_since] && incident.detected_at < @vps[:incident_accounting_since]

      IncidentReport.transaction(requires_new: true) do
        chain, = TransactionChains::IncidentReport::New.fire(incident)
        # Disabled notifications legitimately prepare no chain. Acknowledge the
        # decision separately from the optional real chain identity.
        incident.update!(notification_chain_id: chain&.id, notification_processed_at: @now)
      end
    rescue StandardError => e
      warn "Unable to queue incident #{incident.id}: #{e.class}: #{e.message}"
    end
  end

  def dispatch_actions!
    @vps.vps_incident_actions.where(incident_type: @rule.key, state: %w[pending failed completed]).order(:id).each do |action|
      next if action.retry_after && action.retry_after > @now
      next if action.transaction_chain_id && action.state == 'failed'
      next if %w[sent uncertain suppressed].include?(action.mail_state)
      next if action.mail_state == 'queued'

      unless applicable?(action)
        action.update!(state: 'suppressed', mail_state: 'suppressed')
        next
      end

      VpsIncidentAction.transaction(requires_new: true) do
        if action.kind == 'stop' && action.state != 'completed'
          count30 = counts.last
          unless timely?(action.incident_report) && stop_due?(action.incident_report, count30)
            action.update!(state: 'suppressed', mail_state: 'suppressed')
            next
          end
          chain, = TransactionChains::Vps::Stop.fire(@vps, rollback_stop: false)
          action.update!(transaction_chain: chain, state: 'queued', error: nil)
        else
          if action.kind == 'warning' && (!timely?(action.incident_report) || !warning_due_for_dispatch?(action))
            action.update!(state: 'suppressed', mail_state: 'suppressed')
            next
          end
          first_queue = action.mail_log_id.nil?
          TransactionChains::Vps::IncidentEscalationMail.fire(action)
          policy.update!(last_warning_at: @now) if action.kind == 'warning' && first_queue && action.reload.mail_state == 'queued'
        end
      end
    rescue ResourceLocked => e
      action.reload.update!(error: e.message, retry_after: @now + 60)
    rescue StandardError => e
      action.reload.update!(state: action.state == 'completed' ? 'completed' : 'failed', error: e.message,
                            retry_after: @now + (5 * 60))
      warn "Incident action #{action.id}: #{e.class}: #{e.message}"
    end
  rescue InvalidConfiguration => e
    warn e.message
  end

  def warning_due_for_dispatch?(action)
    return false if config[:mode] == 'observe'
    return false if counts.first < limits.first
    return true if action.mail_log_id # Retry this already queued warning, not a new decision.

    !policy.last_warning_at || policy.last_warning_at <= @now - (7 * DAY)
  end

  def mail_vars(action, language: :en)
    # Snapshot only observed counts. Consequences always describe current settings.
    {
      incident_type: @rule.key, incident_type_label: @rule.label(language),
      user: @vps.user, vps: @vps, base_url: SysConfig.get(:webui, :base_url).to_s,
      incident_count_7d: action.incident_count_7d, incident_count_30d: action.incident_count_30d,
      warning_limit: limits.first,
      stop_limit: limits.last,
      warning_period_days: 7, stop_period_days: 30, repeat_stop_hours: 24,
      incident_at: action.incident_report.detected_at, stop_enforced: stop_enforced?,
      stopped_at: action.completed_at, repeated_stop: action.repeated_stop
    }
  end
end
