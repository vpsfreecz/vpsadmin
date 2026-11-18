require 'digest'

# Decisions and chain preparation share the VPS row lock. The normal resource
# lock still protects physical operations; a busy resource defers this decision.
class IncidentEscalation
  DAY = 24 * 60 * 60
  STATUSES = %w[clear near_limit warning stop_threshold].freeze
  SETTINGS = %w[incident_enforcement_enabled].freeze
  SUMMARY_FIELDS = %i[
    incident_enforcement_enabled incident_last_stop_at incident_next_stop_allowed_at
    incident_action_state incident_action_chain_id incident_accounting_since
    incident_warning_count incident_stop_threshold_count
  ].freeze

  def self.config(values = nil, policy_key:, lock: false)
    selected = rule(policy_key)
    values ||= SysConfig.where(category: selected.category).order(:id).lock(lock).to_h { |row| [row.name, row.value] }
    warning = values['warning_limit']
    stop = values['stop_limit']
    mode = values.fetch('mode', 'observe')
    unless MODES.include?(mode) && [warning, stop].all? { |v| v.nil? || (v.is_a?(Integer) && v.between?(1, 2_147_483_647)) }
      raise InvalidConfiguration, VpsAdmin::API::I18n.t('errors.incident_escalation.invalid_configuration')
    end

    { mode:, warning:, stop: }
  end

  def self.rule(key)
    RULES.fetch(key.to_s) { raise ArgumentError, 'Invalid incident policy' }
  end

  def self.mixed_settings?(attributes)
    keys = attributes.keys.map(&:to_s)
    keys.intersect?(SETTINGS) && (keys - SETTINGS).any?
  end

  def self.serialized(vps, requires_new: false, &block)
    Vps.transaction(requires_new:) do
      SysConfig.where(category: RULES.values.map(&:category)).order(:id).lock.load
      vps = Vps.lock.find_by(id: vps) unless vps.is_a?(Vps)
      vps ? vps.with_lock { block.call(vps) } : block.call(nil)
    end
  end

  def self.update_settings!(vps, attributes)
    attrs = attributes.stringify_keys
    unless attrs.keys == SETTINGS && [true, false].include?(attrs['incident_enforcement_enabled'])
      vps.errors.add(:base, VpsAdmin::API::I18n.t('errors.incident_escalation.separate_update'))
      raise ActiveRecord::RecordInvalid, vps
    end

    serialized(vps) { vps.update!(attrs) }
    vps.incident_summary = nil
  end

  def self.update_policy!(vps, key, attributes)
    selected = rule(key)
    attrs = attributes.stringify_keys
    unless attrs.any? && (attrs.keys - %w[warning_limit_override stop_limit_override]).empty?
      raise ArgumentError, 'Invalid incident policy settings'
    end

    serialized(vps) do
      policy = VpsIncidentPolicy.lock.find_or_initialize_by(vps:, policy_key: selected.key)
      policy.update!(attrs)
      vps.incident_summary = nil
    end
  end

  # Every ordinary model writer shares the same settings/VPS lock order. The
  # caller's save transaction includes insertion, membership and action records.
  def self.create_report!(incident)
    serialized(incident.vps_id) do |vps|
      if vps
        shared = new(vps)
        shared.reconcile_transfer!
        shared.reconcile_actions!
      end
      yield
      evaluate_created_report!(incident, vps)
    end
  end

  def self.evaluate_created_report!(incident, vps)
    now = Time.now.utc
    evaluations = RULES.values.sort_by(&:key).map do |selected|
      engine = new(vps, policy_key: selected.key, now:)
      [engine, engine.evaluate!(incident)]
    end
    stop_group = evaluations.any? { |_engine, evaluation| evaluation.snapshot['decision'] == 'stop' }
    evaluations.each do |engine, evaluation|
      next if stop_group && evaluation.snapshot['decision'] == 'warning'

      engine.create_action!(incident, evaluation)
    end
  end

  # Source validation/dedup remain producer-owned; the model handles evaluation.
  def self.ingest!(vps, attributes:, source_node:, report_message: nil, now: Time.now.utc)
    incident = nil
    serialized(vps) do
      return if vps.node_id != source_node.id

      existing = IncidentReport.lock.find_by(source_key: attributes[:source_key]) if attributes[:source_key]
      return existing if existing

      attributes = attributes.merge(report_message.call(vps, vps.user).slice(:subject, :text)) if report_message
      incident = IncidentReport.create!(attributes.merge(user: vps.user, vps:))
      yield incident if block_given?
    end
    process!(vps, now:)
    incident
  end

  def self.process!(vps, now: Time.now.utc)
    serialized(vps) do
      shared = new(vps, now:)
      shared.reconcile_transfer!
      shared.reconcile_actions!
      shared.dispatch_stop_groups!
      # Removed declarations can still reconcile already submitted physical work
      # and deliver its factual outcome using saved metadata.
      keys = vps.vps_incident_actions.where.not(mail_state: %w[sent suppressed]).order(:id).lock.pluck(:policy_key).uniq
      keys.sort.each { |key| new(vps, policy_key: key, now:).dispatch_actions! }
      shared.queue_incident_reports!
    end
  end

  def initialize(vps, policy_key: nil, now: Time.now.utc)
    @vps = vps
    @policy_key = policy_key
    @rule = RULES[policy_key] if policy_key
    @vps.incident_summary = nil if @vps
    @now = now
  end

  def config
    @config ||= self.class.config(policy_key: @policy_key, lock: true)
  end

  # Mutation reads must see commits newer than a caller's repeatable-read
  # snapshot. Join membership at the locking query's level, not in a subquery.
  def matched_reports
    IncidentReport.joins(:incident_policy_evaluations)
                  .where(incident_policy_evaluations: { policy_key: @policy_key, matched: true })
                  .where(vps_id: @vps.id, user_id: @vps.user_id)
  end

  def counts
    q = matched_reports.where('detected_at <= ? AND detected_at > ?', @now, @now - (30 * DAY))
    q = q.where('detected_at >= ?', @vps[:incident_accounting_since]) if @vps[:incident_accounting_since]
    times = q.order('incident_reports.id').lock.pluck(:detected_at)
    [times.count { |time| time > @now - (7 * DAY) }, times.length]
  end

  def policy
    @policy ||= VpsIncidentPolicy.lock.find_or_initialize_by(vps: @vps, policy_key: @policy_key)
  end

  def applicable?(action)
    action.user_id == @vps.user_id && action.accounting_since == @vps[:incident_accounting_since] &&
      !@vps.incident_owner_transfer_chain_id
  end

  def timely?(incident)
    incident.detected_at.between?(@now - DAY, @now) &&
      (!@vps[:incident_accounting_since] || incident.detected_at >= @vps[:incident_accounting_since])
  end

  def captured_context(incident)
    count7, count30 = counts
    user = @vps.user
    captured = Context.new(
      now: @now.dup.utc, policy_key: @policy_key,
      report: incident.attributes.symbolize_keys.slice(
        :id, :codename, :subject, :text, :detected_at, :created_at, :user_id, :vps_id,
        :filed_by_id, :mailbox_id, :ip_address_assignment_id, :cpu_limit, :vps_action
      ).merge(detected_at: incident.detected_at, created_at: incident.created_at, vps_action: incident.vps_action),
      source: { kind: incident.source_kind, key: incident.source_key, node_id: incident.source_node_id, action: incident.source_action },
      vps: { id: @vps.id, node_id: @vps.node_id, state: @vps.object_state },
      owner: { id: user.id, role: user.role.to_s, state: user.object_state },
      accounting_since: @vps[:incident_accounting_since], count_7d: count7, count_30d: count30,
      last_warning_at: policy.last_warning_at, last_stop_at: @vps[:incident_last_stop_at],
      global_mode: config[:mode], global_overrides: { warning_limit: config[:warning], stop_limit: config[:stop] },
      vps_overrides: { warning_limit: policy.warning_limit_override, stop_limit: policy.stop_limit_override },
      stop_exempt: !@vps.incident_enforcement_enabled
    )
    Context.new(**captured.to_h.transform_values { |value| self.class.freeze_values(value) }).freeze
  end

  # Applying deterministic current restrictions never calls site Ruby again.
  def effective_result(base, policy: self.policy, config: self.config)
    result = base.merge(
      'warning_limit' => policy&.warning_limit_override || config[:warning] || base.fetch('warning_limit'),
      'stop_limit' => policy&.stop_limit_override || config[:stop] || base.fetch('stop_limit'),
      'mode' => MODES[[MODES.index(base.fetch('mode')), MODES.index(config[:mode])].min],
      'stop_exempt' => !@vps.incident_enforcement_enabled
    )
    if result['stop_limit'] < result['warning_limit']
      raise InvalidConfiguration, VpsAdmin::API::I18n.t('errors.incident_escalation.invalid_configuration')
    end

    result
  end

  def evaluate!(incident)
    snapshot = { 'policy_digest' => self.class.policy_digest, 'policy_source' => self.class.site_policy? ? 'site' : 'builtin',
                 'evaluated_at' => @now.iso8601(6), 'decision' => 'none', 'metadata' => @rule.metadata }
    outcome = IncidentPolicyEvaluation.new(incident_report: incident, policy_key: @policy_key, evaluated_at: @now)
    unless @vps && @vps.user && incident.user_id == @vps.user_id && !@vps.incident_owner_transfer_chain_id &&
           (!@vps[:incident_accounting_since] || incident.detected_at >= @vps[:incident_accounting_since])
      outcome.state = 'audit_only'
      outcome.matched = false
      outcome.snapshot = snapshot.merge('state' => outcome.state)
      outcome.save!
      return outcome
    end

    stage = 'selection'
    ctx = captured_context(incident)
    snapshot['context'] = ctx.to_h.except(:report).as_json
    matched = @rule.selector ? @rule.selector.call(ctx) : true
    raise InvalidConfiguration, 'Incident selector must return true or false' unless [true, false].include?(matched)

    outcome.matched = matched
    outcome.state = (if timely?(incident)
                       matched ? 'recorded' : 'skipped'
                     else
                       'audit_only'
                     end)
    # Persist membership before counting this event. This row and the report
    # remain in the enclosing transaction until every outcome is complete.
    outcome.snapshot = snapshot.merge('state' => outcome.state)
    outcome.save!
    if matched
      stage = 'configuration'
      count7, count30 = counts
      snapshot['context'] = snapshot.fetch('context').merge('count_7d' => count7, 'count_30d' => count30)
      result = effective_result(@rule.base)
      snapshot.merge!('base' => @rule.base, 'effective' => result)
      if outcome.state == 'recorded' && @vps.object_state == 'active' && @vps.user.object_state == 'active' && !%w[stop suspend].include?(incident.vps_action) && !result['suppress_actions'] && !@vps.vps_incident_actions.outstanding_stops.lock.exists?
        stage = 'decision'
        last_stop = @vps[:incident_last_stop_at]
        if result['mode'] == 'enforce' && !result['stop_exempt'] && count30 >= result['stop_limit'] &&
           (!last_stop || (incident.detected_at > last_stop && incident.detected_at >= last_stop + DAY))
          snapshot['decision'] = 'stop'
        elsif result['mode'] != 'observe' && count7 >= result['warning_limit'] &&
              (!policy.last_warning_at || policy.last_warning_at <= @now - (7 * DAY)) &&
              !@vps.vps_incident_actions.where(policy_key: @policy_key, kind: 'warning', state: %w[pending queued failed]).lock.exists?
          snapshot['decision'] = 'warning'
        end
      end
    end
    # attr_readonly protects later callers; ingestion completes the initial
    # snapshot within this transaction before it becomes externally visible.
    IncidentPolicyEvaluation.where(id: outcome.id).update_all(snapshot: snapshot.merge('state' => outcome.state))
    outcome.reload
  rescue StandardError => e
    raise if e.is_a?(ActiveRecord::ActiveRecordError)

    warn "Incident policy #{@policy_key}: #{e.class}; automatic actions are disabled"
    error_snapshot = snapshot.merge('state' => 'error', 'decision' => 'none', 'error_stage' => stage, 'error_class' => e.class.name)
    if outcome.persisted?
      IncidentPolicyEvaluation.where(id: outcome.id).update_all(state: 'error', snapshot: error_snapshot)
      outcome.reload
    else
      outcome.assign_attributes(state: 'error', snapshot: error_snapshot)
      outcome.save!
      outcome
    end
  end

  def contributor_snapshot(incident, kind)
    days = kind == 'warning' ? 7 : 30
    scope = matched_reports.where('detected_at > ? AND detected_at <= ?', @now - (days * DAY), @now)
    scope = scope.where('detected_at >= ?', @vps[:incident_accounting_since]) if @vps[:incident_accounting_since]
    entries = scope.select('incident_reports.id', 'incident_reports.subject', 'incident_reports.detected_at')
                   .order(detected_at: :desc, id: :desc).lock.to_a
    total = entries.length
    selected = entries.take(5)
    if selected.none? { |entry| entry.id == incident.id } && (trigger = entries.find { |entry| entry.id == incident.id })
      selected = selected.take(4) + [trigger]
    end
    selected.sort_by! { |entry| [entry.detected_at, entry.id] }.reverse!
    evaluation = incident.incident_policy_evaluations.lock.find_by!(policy_key: @policy_key).snapshot
    evaluation = evaluation.slice('state', 'policy_digest', 'policy_source', 'evaluated_at', 'metadata', 'base', 'effective', 'decision', 'context')
    evaluation['context'] = evaluation.fetch('context').slice('count_7d', 'count_30d')
    { 'total' => total, 'window_days' => days, 'decision_at' => @now.iso8601(6), 'policy' => evaluation,
      'entries' => selected.map do |entry|
        { 'id' => entry.id, 'detected_at' => entry.detected_at.iso8601,
          'subject' => entry.subject.gsub(/[[:cntrl:]]/, ' ').first(160) }
      end }
  end

  def create_notice!(action)
    return if action.notice_incident_report_id
    return unless action.kind == 'warning' || action.state == 'completed'

    message = VpsAdmin::API::IncidentReports.escalation_message(action)
    notice = IncidentReport.create!(user_id: action.user_id, vps_id: action.vps_id, codename: action.policy_key,
                                    source_kind: 'incident_policy_notice', vps_action: :none,
                                    detected_at: action.completed_at || action.created_at, reported_at: @now,
                                    notification_processed_at: @now, **message)
    action.update!(notice_incident_report: notice)
  end

  def create_action!(incident, evaluation)
    return unless evaluation.state == 'recorded'

    kind = evaluation.snapshot['decision']
    return if kind == 'none'

    if kind == 'stop'
      @vps.vps_incident_actions.where(policy_key: @policy_key, kind: 'warning', state: %w[pending failed])
          .update_all(state: 'suppressed', mail_state: 'suppressed')
    end
    action = @vps.vps_incident_actions.create!(
      user_id: @vps.user_id, incident_report: incident, incident_policy_evaluation: evaluation,
      policy_key: @policy_key, accounting_since: @vps[:incident_accounting_since],
      kind:, incident_count_7d: evaluation.snapshot['context']['count_7d'], incident_count_30d: evaluation.snapshot['context']['count_30d'],
      contributor_snapshot: contributor_snapshot(incident, kind),
      repeated_stop: !@vps[:incident_last_stop_at].nil? && (!@vps[:incident_accounting_since] || @vps[:incident_last_stop_at] >= @vps[:incident_accounting_since])
    )
    create_notice!(action) if kind == 'warning'
  end

  # Confirmations bypass callbacks. Keep the marker until the complete transfer
  # succeeds, then use its physical Chown timestamp as the new accounting epoch.
  def reconcile_transfer!
    return unless @vps.incident_owner_transfer_chain_id

    chain = TransactionChain.lock.find(@vps.incident_owner_transfer_chain_id)
    if chain.done?
      transaction = chain.transactions.lock.find_by(handle: Transactions::Vps::Chown.t_type, status: [1, 2], done: 1)
      return unless transaction&.finished_at

      @vps.update_columns(incident_accounting_since: transaction.finished_at, incident_owner_transfer_chain_id: nil)
      @vps.vps_incident_policies.update_all(last_warning_at: nil)
    elsif chain.failed?
      @vps.update_columns(incident_owner_transfer_chain_id: nil)
    end
  end

  def reconcile_actions!
    @vps.vps_incident_actions.where.not(state: 'suppressed').where.not(state: 'completed', mail_state: %w[sent suppressed]).lock.find_each do |action|
      if action.kind == 'stop' && action.transaction_chain_id && %w[queued failed uncertain].include?(action.state)
        chain = TransactionChain.lock.find(action.transaction_chain_id)
        transaction = chain.transactions.lock.find_by(handle: Transactions::Vps::Stop.t_type)
        if chain.done? && transaction&.done == 'done' && [1, 2].include?(transaction.status) && transaction.finished_at
          action.update!(state: 'completed', completed_at: transaction.finished_at, error: nil)
          @vps.update_columns(incident_last_stop_at: [@vps[:incident_last_stop_at], transaction.finished_at].compact.max) unless action.stop_owner_action_id
          create_notice!(action)
        elsif %w[failed fatal resolved done].include?(chain.state)
          action.update!(state: chain.failed? ? 'failed' : 'uncertain', error: 'Stop outcome requires operator reconciliation')
        end
      end
      next unless action.mail_state == 'queued'

      log = MailLog.lock.find_by(id: action.mail_log_id)
      transaction = log && Transaction.lock.find_by(id: log.transaction_id)
      if transaction&.done == 'done'
        action.update!(mail_state: [1, 2].include?(transaction.status) ? 'sent' : 'failed', retry_after: @now + (5 * 60))
        action.update!(state: action.mail_state == 'sent' ? 'completed' : 'failed') if action.kind == 'warning'
      elsif action.mail_chain_id && %w[failed fatal resolved].include?(TransactionChain.lock.find(action.mail_chain_id).state)
        action.update!(mail_state: 'uncertain', error: 'Mail outcome requires operator reconciliation')
      end
    end
  end

  def queue_incident_reports!
    IncidentReport.ordinary.where(vps_id: @vps.id, source_kind: 'node_vps_event', notification_processed_at: nil).where.not(source_key: nil).lock.find_each do |incident|
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

  def dispatch_stop_groups!
    pending = @vps.vps_incident_actions.where(kind: 'stop', state: %w[pending failed], transaction_chain_id: nil)
                  .order(:incident_report_id, :policy_key, :id).lock.to_a.group_by(&:incident_report_id)
    pending.each_value do |group|
      group.sort_by! { |action| [action.policy_key, action.id] }
      next if group.any? { |action| action.retry_after && action.retry_after > @now }
      # Submitted, failed and uncertain physical work keeps its exclusion. A
      # follower can never be elected to replay a previously submitted chain.
      break if @vps.vps_incident_actions.outstanding_stops.where.not(transaction_chain_id: nil).lock.exists?

      VpsIncidentAction.transaction(requires_new: true) do
        eligible = group.select do |action|
          engine = self.class.new(@vps, policy_key: action.policy_key, now: @now)
          allowed = engine.applicable?(action) && engine.decision_allowed?(action)
          action.update!(state: 'suppressed', mail_state: 'suppressed') unless allowed
          allowed
        rescue InvalidConfiguration
          action.update!(state: 'suppressed', mail_state: 'suppressed')
          false
        end
        next if eligible.empty?

        owner = eligible.first
        chain, = TransactionChains::Vps::Stop.fire(@vps, rollback_stop: false)
        eligible.each do |action|
          action.update!(transaction_chain: chain, stop_owner_action_id: action == owner ? nil : owner.id,
                         state: 'queued', error: nil)
        end
      end
    rescue ResourceLocked => e
      group.each { |action| action.reload.update!(error: e.class.name, retry_after: @now + 60) }
    rescue StandardError => e
      group.each do |action|
        action.reload.update!(state: 'failed', error: e.class.name, retry_after: @now + (5 * 60)) unless action.state == 'suppressed'
      end
      warn "Incident stop group: #{e.class}"
    end
  end

  def dispatch_actions!
    @vps.vps_incident_actions.where(policy_key: @policy_key, state: %w[pending failed completed]).order(:id).lock.each do |action|
      next if action.kind == 'stop' && action.state != 'completed'
      next if action.retry_after && action.retry_after > @now
      next if action.transaction_chain_id && action.state == 'failed'
      next if %w[sent uncertain suppressed].include?(action.mail_state)
      next if action.mail_state == 'queued'

      unless applicable?(action)
        action.update!(state: 'suppressed', mail_state: 'suppressed')
        next
      end

      VpsIncidentAction.transaction(requires_new: true) do
        if action.kind == 'warning' && !decision_allowed?(action)
          action.update!(state: 'suppressed', mail_state: 'suppressed', error: 'Decision no longer eligible under loaded policy/settings')
          next
        end
        first_queue = action.mail_log_id.nil?
        TransactionChains::Vps::IncidentEscalationMail.fire(action)
        policy.update!(last_warning_at: @now) if action.kind == 'warning' && first_queue && action.reload.mail_state == 'queued'
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

  def action_result(action)
    saved = action.saved_policy_evaluation.fetch('effective')
    return effective_result(action.saved_policy_evaluation.fetch('base')) if @rule

    # Retired declarations cannot dispatch a new action. A submitted stop still
    # has a factual outcome whose saved limits remain available for its notice.
    saved.merge('mode' => 'observe', 'suppress_actions' => true, 'stop_exempt' => !@vps.incident_enforcement_enabled)
  end

  def decision_allowed?(action)
    trigger = IncidentReport.lock.find_by(id: action.incident_report_id)
    return false unless @rule && trigger && @vps.object_state == 'active' && @vps.user&.object_state == 'active'

    evaluation = action.saved_policy_evaluation
    undispatched = action.transaction_chain_id.nil? && action.mail_chain_id.nil? && action.mail_log_id.nil?
    return false if undispatched && (!evaluation || evaluation['policy_digest'] != self.class.policy_digest)
    return false unless timely?(trigger)

    result = action_result(action)
    saved = evaluation&.fetch('effective', nil) || result
    return false if saved['suppress_actions'] || result['suppress_actions']

    mode = MODES[[MODES.index(saved['mode']), MODES.index(result['mode'])].min]
    if action.kind == 'stop'
      return false unless mode == 'enforce' && !result['stop_exempt'] && !saved['stop_exempt']
      return false if counts.last < [saved['stop_limit'], result['stop_limit']].max

      last_stop = @vps[:incident_last_stop_at]
      !last_stop || trigger.detected_at >= last_stop + DAY
    else
      mode != 'observe' && counts.first >= [saved['warning_limit'], result['warning_limit']].max &&
        (action.mail_log_id || !policy.last_warning_at || policy.last_warning_at <= @now - (7 * DAY))
    end
  end

  def mail_vars(action, language: :en)
    result = action_result(action)
    trigger_time = action.incident_report&.detected_at
    saved_trigger = action.contributor_snapshot&.fetch('entries')&.find { |entry| entry['id'] == action.incident_report_id }
    trigger_time ||= Time.iso8601(saved_trigger.fetch('detected_at')) if saved_trigger
    {
      incident_type: action.policy_key, incident_type_label: action.saved_policy_evaluation.fetch('metadata').fetch('labels').fetch(language.to_s) { action.saved_policy_evaluation.fetch('metadata').fetch('labels').fetch('en') },
      user: @vps.user, vps: @vps, base_url: SysConfig.get(:webui, :base_url).to_s,
      incident_count_7d: action.incident_count_7d, incident_count_30d: action.incident_count_30d,
      warning_limit: result['warning_limit'],
      stop_limit: result['stop_limit'],
      warning_period_days: 7, stop_period_days: 30, repeat_stop_hours: 24,
      incident_at: trigger_time,
      stop_enforced: result['mode'] == 'enforce' && !result['stop_exempt'] && !result['suppress_actions'],
      stopped_at: action.completed_at, repeated_stop: action.repeated_stop
    }.merge(contributor_mail_vars(action))
  end

  def contributor_mail_vars(action)
    history_url = VpsAdmin::API::IncidentReports.webui_url(page: 'incidents', action: 'list', list: 1,
                                                           vps: action.vps_id, policy_key: action.policy_key)
    snapshot = action.contributor_snapshot
    entries = snapshot ? snapshot.fetch('entries') : []
    authorized = applicable?(action)
    reports = if authorized
                IncidentReport.where(id: IncidentPolicyEvaluation.where(policy_key: action.policy_key, matched: true).select(:incident_report_id)).where(id: entries.map { |entry| entry['id'] }, vps_id: action.vps_id,
                                                                                                                                                         user_id: action.user_id).index_by(&:id)
              else
                {}
              end
    selected = entries.map do |entry|
      report = reports[entry['id']]
      available = report && (!action.accounting_since || report.detected_at >= action.accounting_since)
      { id: entry['id'], available: available == true, subject: available ? entry['subject'] : nil,
        detected_at: available ? Time.iso8601(entry['detected_at']) : nil,
        url: available ? VpsAdmin::API::IncidentReports.webui_url(page: 'incidents', action: 'show', id: entry['id']) : nil }
    end
    trigger = action.incident_report if !snapshot && authorized && action.incident_report && action.incident_report.user_id == action.user_id &&
                                        action.incident_report.vps_id == action.vps_id &&
                                        (!action.accounting_since || action.incident_report.detected_at >= action.accounting_since)
    {
      contributor_snapshot_available: !snapshot.nil?, contributing_incidents: selected,
      contributing_incident_count: snapshot&.fetch('total'), contributing_incident_shown: selected.length,
      contributing_incident_omitted: snapshot && (snapshot.fetch('total') - selected.length),
      contributing_incident_window_days: snapshot&.fetch('window_days'), decision_at: snapshot && Time.iso8601(snapshot.fetch('decision_at')),
      incident_history_url: authorized ? history_url : nil,
      trigger_incident: trigger && { id: trigger.id, detected_at: trigger.detected_at,
                                     subject: trigger.subject.gsub(/[[:cntrl:]]/, ' ').first(160), available: true,
                                     url: VpsAdmin::API::IncidentReports.webui_url(page: 'incidents', action: 'show', id: trigger.id) }
    }
  end
end
