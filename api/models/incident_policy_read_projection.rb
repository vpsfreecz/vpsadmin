require 'time'
require 'uri'

# Administrative reads share saved membership with the engine, but never run
# selectors or reconcile outcomes. Each collection selects its total, ordered
# page and all mutable facts in one statement, including inside DailyReport's
# existing write transaction on READ-COMMITTED installations.
class IncidentPolicyReadProjection
  DAY = IncidentEscalation::DAY
  SORTS = %w[severity vps_id user_login policy_key count_7d count_30d warning_remaining stop_remaining last_incident_at].freeze
  ACTION_STATES = %w[pending queued failed uncertain completed suppressed].freeze
  MAIL_STATES = %w[pending queued sent failed uncertain suppressed].freeze
  EXPOSURE_TYPES = {
    string: %i[id hostname user_login node_name policy_key label global_mode effective_mode status outstanding_stop_state
               latest_action_kind latest_action_state latest_mail_state],
    integer: %i[vps_id user_id node_id count_7d count_30d warning_period_days stop_period_days warning_limit stop_limit
                warning_remaining stop_remaining outstanding_stop_action_id outstanding_stop_chain_id latest_action_id
                latest_action_chain_id latest_notice_report_id],
    bool: %i[owner_active transfer_pending configuration_valid warning_permitted stop_enforced],
    datetime: %i[last_incident_at last_warning_at next_warning_allowed_at last_stop_at next_stop_allowed_at accounting_since
                 latest_stop_completed_at]
  }.freeze
  HISTORY_TYPES = {
    string: %i[hostname user_login policy_key label state effective_mode threshold_status decision action_kind action_state mail_state],
    integer: %i[id incident_report_id vps_id user_id warning_period_days stop_period_days count_7d count_30d warning_limit stop_limit
                action_id transaction_chain_id physical_stop_action_id notice_report_id],
    bool: %i[matched stop_enforced],
    datetime: %i[evaluated_at detected_at action_created_at action_updated_at stop_completed_at mail_queued_at mail_finished_at]
  }.freeze

  attr_reader :as_of, :read_at

  def initialize(as_of: nil, now: Time.now.utc, language: :en)
    @read_at = now.utc
    @as_of = Time.at((as_of || now).to_time.to_i).utc
    raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.cutoff') if @as_of > @read_at || @as_of < @read_at - DAY

    @language = language.to_s
    @rules = IncidentEscalation::RULES.values.dup
    settings = SysConfig.where(category: @rules.map(&:category)).order(:id).to_a.group_by(&:category)
    @configs = @rules.to_h do |rule|
      values = settings.fetch(rule.category, []).to_h { |row| [row.name, row.value] }
      config = begin
        IncidentEscalation.config(values, policy_key: rule.key)
      rescue IncidentEscalation::InvalidConfiguration
        nil
      end
      [rule.key, { config:, global_mode: values.fetch('mode', 'observe').to_s }]
    end
  end

  def exposures(**options)
    policy = options[:policy_key]
    raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.policy') if policy && @rules.none? { |rule| rule.key == policy }

    validate_choice(options, :status, IncidentEscalation::STATUSES + ['invalid'])
    validate_choice(options, :effective_mode, IncidentEscalation::MODES)
    sort = options.fetch(:sort, 'severity')
    raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.sort') unless SORTS.include?(sort)

    direction = options.fetch(:direction, sort == 'severity' ? 'desc' : 'asc')
    raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.direction') unless %w[asc desc].include?(direction)

    filters = equality_filters(options, %i[vps_id user_id node_id policy_key effective_mode stop_enforced])
    if options[:status]
      filters << (options[:status] == 'invalid' ? 'configuration_valid = FALSE' : "status = #{q(options[:status])}")
    end
    pairs = @rules.select { |rule| !policy || rule.key == policy }.map { |rule| exposure_sql(rule) }
    # Empty registries still have a typed relation and honest zero metadata.
    pairs << 'SELECT NULL AS id WHERE FALSE' if pairs.empty?
    primary = sort == 'policy_key' ? 'BINARY policy_key' : sort
    order = "#{primary} IS NULL, #{primary} #{direction}, remaining IS NULL, remaining ASC, last_incident_at DESC, vps_id ASC, BINARY policy_key ASC"
    if @rules.empty?
      return empty_page(options)
    end

    sql = <<~SQL
      #{action_ctes}, pairs AS (#{pairs.join(' UNION ALL ')}),
      facts AS (SELECT pairs.*,
        CASE WHEN outstanding_stop_state IN ('failed','uncertain') THEN 5 WHEN NOT configuration_valid THEN 4
          WHEN outstanding_stop_state = 'pending' THEN 3 WHEN status = 'stop_threshold' THEN 2
          WHEN status = 'warning' THEN 1 WHEN status = 'near_limit' THEN 0 ELSE -1 END AS severity,
        LEAST(warning_remaining, stop_remaining) AS remaining FROM pairs)
    SQL
    page(sql, 'facts', filters, order, options, EXPOSURE_TYPES) do |row|
      row[:label] = @rules.find { |rule| rule.key == row[:policy_key] }.label(@language)
      row
    end
  end

  def history(activity: false, **options)
    validate_choice(options, :scope, %w[violations matched all outstanding])
    validate_choice(options, :decision, %w[none warning stop])
    validate_choice(options, :action_kind, %w[warning stop])
    validate_choice(options, :action_state, ACTION_STATES)
    validate_choice(options, :mail_state, MAIL_STATES)
    direction = options.fetch(:direction, 'desc')
    raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.direction') unless %w[asc desc].include?(direction)

    scope = options.fetch(:scope, 'violations')
    filters = equality_filters(options, %i[policy_key vps_id user_id decision action_kind action_state mail_state])
    if scope == 'outstanding'
      filters << "action_state != 'suppressed' AND (action_state IN ('pending','queued','failed','uncertain') OR mail_state IN ('pending','queued','failed','uncertain'))"
      from = to = nil
    else
      from = options[:from] || (@as_of - (30 * DAY))
      to = options[:to] || @as_of
      raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.period') unless from < to && to <= @as_of && to - from <= 366 * DAY

      filters << "evaluated_at >= #{q(from)} AND evaluated_at < #{q(to)}" unless activity
      filters << 'matched = TRUE' if scope == 'matched'
      if activity
        filters << "(decision IN ('warning','stop') OR threshold_status IN ('warning','stop_threshold') OR action_id IS NOT NULL)"
      elsif scope == 'violations'
        filters << "(threshold_status IN ('warning','stop_threshold') OR action_id IS NOT NULL)"
      end
    end
    sql = "#{action_ctes}, history AS (#{history_sql})"
    relation = 'history'
    order = "evaluated_at #{direction}, id #{direction}"
    if activity
      sql += ", activity AS (#{activity_sql(from, to)})"
      relation = 'activity'
      filters << 'activity_at IS NOT NULL'
      order = 'activity_at DESC, id DESC'
    end
    types = activity ? HISTORY_TYPES.merge(datetime: HISTORY_TYPES[:datetime] + [:activity_at], string: HISTORY_TYPES[:string] + [:activity_basis]) : HISTORY_TYPES
    result = page(sql, relation, filters, order, options, types) { |row| history_row(row) }
    result[:meta].merge!(from:, to:)
    result
  end

  def daily_summary(base_url: nil)
    start = @as_of - DAY
    collections = {
      overview: exposures(limit: 25),
      activity: history(activity: true, from: start, to: @as_of, limit: 25),
      outstanding: history(scope: 'outstanding', limit: 25)
    }
    base = safe_base_url(base_url)
    result = { as_of: @as_of, period_start: start, period_end: @as_of }
    collections.each do |name, collection|
      rows = collection[:rows].map { |row| row.merge(prepared_links(base, row)) }
      params = { page: 'incidents', action: name == :overview ? 'overview' : 'history' }
      params[:scope] = 'outstanding' if name == :outstanding
      params.merge!(scope: 'violations', from: start.iso8601, to: @as_of.iso8601) if name == :activity
      result[name] = { total_count: collection[:meta][:total_count], rows:,
                       omitted_count: collection[:meta][:total_count] - rows.length, url: link(base, params) }
    end
    result
  end

  protected

  def q(value) = Vps.connection.quote(value)

  def validate_choice(options, key, choices)
    return unless options[key] && !choices.include?(options[key])

    fields = {
      status: VpsAdmin::API::I18n.t('errors.incident_policy_read.fields.status'),
      effective_mode: VpsAdmin::API::I18n.t('errors.incident_policy_read.fields.effective_mode'),
      scope: VpsAdmin::API::I18n.t('errors.incident_policy_read.fields.scope'),
      decision: VpsAdmin::API::I18n.t('errors.incident_policy_read.fields.decision'),
      action_kind: VpsAdmin::API::I18n.t('errors.incident_policy_read.fields.action_kind'),
      action_state: VpsAdmin::API::I18n.t('errors.incident_policy_read.fields.action_state'),
      mail_state: VpsAdmin::API::I18n.t('errors.incident_policy_read.fields.mail_state')
    }
    raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.choice', field: fields.fetch(key))
  end

  def equality_filters(options, keys)
    keys.filter_map { |key| "#{key} = #{q(options[key])}" if options.has_key?(key) && !options[key].nil? }
  end

  def empty_page(options)
    offset = options.fetch(:offset, 0)
    limit = options.fetch(:limit, 25)
    raise ArgumentError, VpsAdmin::API::I18n.t('errors.incident_policy_read.page') unless offset.is_a?(Integer) && offset >= 0 && limit.is_a?(Integer) && limit.between?(1, 100)

    { rows: [], meta: { total_count: 0, offset:, limit:, next_offset: nil, as_of: @as_of, read_at: @read_at } }
  end

  def page(ctes, relation, filters, order, options, types)
    result = empty_page(options)
    offset, limit = result[:meta].values_at(:offset, :limit)
    where = filters.empty? ? 'TRUE' : filters.join(' AND ')
    sql = <<~SQL
      #{ctes}, filtered AS (SELECT * FROM #{relation} WHERE #{where}),
      page AS (SELECT * FROM filtered ORDER BY #{order} LIMIT #{limit} OFFSET #{offset})
      SELECT page.*, totals.total_count FROM (SELECT COUNT(*) AS total_count FROM filtered) totals
      LEFT JOIN page ON TRUE ORDER BY #{order}
    SQL
    selected = Vps.connection.select_all(sql).to_a
    result[:meta][:total_count] = selected.first.fetch('total_count').to_i
    result[:rows] = selected.filter_map do |raw|
      next if raw['id'].nil?

      row = types.each_with_object({}) do |(type, fields), values|
        fields.each { |field| values[field] = cast(raw[field.to_s], type) }
      end
      row[:_snapshot] = raw['_snapshot'] if raw.has_key?('_snapshot')
      yield row
    end
    next_offset = offset + result[:rows].length
    result[:meta][:next_offset] = next_offset if next_offset < result[:meta][:total_count]
    result
  end

  def cast(value, type)
    return if value.nil?

    case type
    when :integer then value.to_i
    when :bool then [true, 1, '1'].include?(value)
    when :datetime then value.is_a?(String) ? Time.parse("#{value} UTC").utc : value.to_time.utc
    else value.to_s
    end
  end

  def action_ctes
    <<~SQL
      WITH completed_stops AS (
        SELECT t.transaction_chain_id, MAX(t.finished_at) AS stopped_at FROM transactions t
        JOIN transaction_chains c ON c.id = t.transaction_chain_id AND c.state = 2
        WHERE t.handle = 1002 AND t.done = 1 AND t.status IN (1,2) AND t.finished_at IS NOT NULL
        GROUP BY t.transaction_chain_id
      ), action_mail AS (
        SELECT a.*, COALESCE(owner.transaction_chain_id, a.transaction_chain_id) AS physical_chain_id,
          CASE WHEN a.kind = 'stop' THEN COALESCE(a.stop_owner_action_id, a.id) END AS physical_stop_action_id,
          CASE WHEN a.kind = 'stop' THEN stops.stopped_at END AS stop_completed_at,
          m.created_at AS mail_queued_at,
          CASE WHEN mt.done = 1 THEN mt.finished_at END AS mail_finished_at,
          CASE WHEN a.mail_state = 'suppressed' THEN 'suppressed'
            WHEN mt.done = 1 AND mt.status IN (1,2) THEN 'sent' WHEN mt.done = 1 THEN 'failed'
            WHEN a.mail_state = 'queued' AND mc.state IN (4,5,6) THEN 'uncertain' ELSE a.mail_state END AS current_mail_state,
          c.state AS chain_state
        FROM vps_incident_actions a LEFT JOIN vps_incident_actions owner ON owner.id = a.stop_owner_action_id
        LEFT JOIN completed_stops stops ON stops.transaction_chain_id = COALESCE(owner.transaction_chain_id, a.transaction_chain_id)
        LEFT JOIN transaction_chains c ON c.id = COALESCE(owner.transaction_chain_id, a.transaction_chain_id)
        LEFT JOIN mail_logs m ON m.id = a.mail_log_id LEFT JOIN transactions mt ON mt.id = m.transaction_id AND mt.handle = 9001
        LEFT JOIN transaction_chains mc ON mc.id = a.mail_chain_id
      ), action_facts AS (
        SELECT action_mail.*,
          CASE WHEN state = 'suppressed' THEN 'suppressed' WHEN kind = 'stop' AND stop_completed_at IS NOT NULL THEN 'completed'
            WHEN kind = 'stop' AND state IN ('queued','failed','uncertain') AND chain_state = 2 THEN 'uncertain'
            WHEN kind = 'warning' AND current_mail_state = 'sent' THEN 'completed'
            WHEN kind = 'warning' AND current_mail_state = 'failed' THEN 'failed'
            WHEN state IN ('failed','uncertain') THEN state WHEN chain_state = 4 THEN 'failed'
            WHEN chain_state IN (5,6) THEN 'uncertain' ELSE state END AS current_action_state
        FROM action_mail
      )
    SQL
  end

  def exposure_sql(rule)
    captured = @configs.fetch(rule.key)
    config = captured[:config]
    warning = "COALESCE(incident_policy.warning_limit_override, #{q((config && config[:warning]) || rule.warning_limit)})"
    stop = "COALESCE(incident_policy.stop_limit_override, #{q((config && config[:stop]) || rule.stop_limit)})"
    valid = "(#{config ? 'TRUE' : 'FALSE'} AND #{warning} > 0 AND #{stop} >= #{warning})"
    mode = config && IncidentEscalation::MODES[[IncidentEscalation::MODES.index(rule.base.fetch('mode')), IncidentEscalation::MODES.index(config[:mode])].min]
    status = <<~SQL.squish
      CASE WHEN NOT #{valid} THEN NULL WHEN incident_counts.count30 >= #{stop} THEN 'stop_threshold'
        WHEN incident_counts.count7 >= #{warning} THEN 'warning'
        WHEN incident_counts.count7 >= CEIL(0.8 * #{warning}) OR incident_counts.count30 >= CEIL(0.8 * #{stop}) THEN 'near_limit' ELSE 'clear' END
    SQL
    last_stop = 'GREATEST(COALESCE(vpses.incident_last_stop_at, confirmed.stopped_at), COALESCE(confirmed.stopped_at, vpses.incident_last_stop_at))'
    <<~SQL.squish
      SELECT CONCAT(vpses.id, ':', #{q(rule.key)}) AS id, vpses.id AS vps_id, vpses.user_id, vpses.node_id,
        vpses.hostname, users.login AS user_login, CONCAT(nodes.name, '.', locations.domain) AS node_name, #{q(rule.key)} AS policy_key,
        users.object_state = #{q(User.object_states[:active])} AS owner_active,
        (vpses.incident_owner_transfer_chain_id IS NOT NULL AND incident_chown.finished_at IS NULL) AS transfer_pending,
        incident_counts.count7 AS count_7d, incident_counts.count30 AS count_30d, 7 AS warning_period_days, 30 AS stop_period_days,
        IF(#{valid}, #{warning}, NULL) AS warning_limit, IF(#{valid}, #{stop}, NULL) AS stop_limit,
        IF(#{valid}, GREATEST(#{warning} - incident_counts.count7, 0), NULL) AS warning_remaining,
        IF(#{valid}, GREATEST(#{stop} - incident_counts.count30, 0), NULL) AS stop_remaining,
        #{valid} AS configuration_valid, #{status} AS status, #{q(captured[:global_mode])} AS global_mode,
        IF(#{valid}, #{q(mode)}, NULL) AS effective_mode,
        IF(#{valid}, #{q(mode != 'observe' && !rule.base['suppress_actions'])}, NULL) AS warning_permitted,
        IF(#{valid}, #{q(mode == 'enforce' && !rule.base['suppress_actions'])} AND vpses.incident_enforcement_enabled, NULL) AS stop_enforced,
        incident_counts.last_incident AS last_incident_at,
        IF(incident_chown.finished_at IS NULL, incident_policy.last_warning_at, NULL) AS last_warning_at,
        IF(incident_chown.finished_at IS NULL, DATE_ADD(incident_policy.last_warning_at, INTERVAL 7 DAY), NULL) AS next_warning_allowed_at,
        #{last_stop} AS last_stop_at, DATE_ADD(#{last_stop}, INTERVAL 1 DAY) AS next_stop_allowed_at,
        COALESCE(incident_chown.finished_at, vpses.incident_accounting_since) AS accounting_since,
        CASE WHEN outstanding.current_action_state IN ('failed','uncertain') THEN outstanding.current_action_state
          WHEN outstanding.id IS NOT NULL THEN 'pending' ELSE 'none' END AS outstanding_stop_state,
        outstanding.id AS outstanding_stop_action_id, outstanding.physical_chain_id AS outstanding_stop_chain_id,
        latest.id AS latest_action_id, latest.transaction_chain_id AS latest_action_chain_id,
        latest.notice_incident_report_id AS latest_notice_report_id, latest.kind AS latest_action_kind,
        latest.current_action_state AS latest_action_state, latest.current_mail_state AS latest_mail_state,
        latest.stop_completed_at AS latest_stop_completed_at
      FROM vpses JOIN users ON users.id = vpses.user_id JOIN nodes ON nodes.id = vpses.node_id JOIN locations ON locations.id = nodes.location_id
      JOIN vpses accounting_vps ON accounting_vps.id = vpses.id #{VpsIncidentSummary.accounting_join}
      #{VpsIncidentSummary.count_join(@as_of, rule.key, evaluated_before: @as_of)} #{VpsIncidentSummary.policy_join(rule.key)}
      LEFT JOIN (SELECT vps_id, MAX(stop_completed_at) AS stopped_at FROM action_facts WHERE stop_owner_action_id IS NULL GROUP BY vps_id) confirmed ON confirmed.vps_id = vpses.id
      LEFT JOIN action_facts outstanding ON outstanding.id = (SELECT MAX(o.id) FROM action_facts o WHERE o.vps_id = vpses.id
        AND o.kind = 'stop' AND o.stop_owner_action_id IS NULL AND o.current_action_state IN ('pending','queued','failed','uncertain'))
      LEFT JOIN action_facts latest ON latest.id = (SELECT MAX(a.id) FROM action_facts a
        JOIN incident_policy_evaluations e ON e.id = a.incident_policy_evaluation_id
        WHERE a.vps_id = vpses.id AND a.user_id = vpses.user_id AND a.policy_key = #{q(rule.key)}
          AND a.accounting_since <=> COALESCE(incident_chown.finished_at, vpses.incident_accounting_since) AND e.evaluated_at <= #{q(@as_of)})
      WHERE vpses.object_state = #{q(Vps.object_states[:active])} AND incident_counts.count30 > 0
    SQL
  end

  def json_integer(path)
    value = "JSON_EXTRACT(e.snapshot, '#{path}')"
    "IF(BINARY JSON_TYPE(#{value}) = BINARY 'INTEGER' AND CAST(#{value} AS SIGNED) >= 0, CAST(#{value} AS SIGNED), NULL)"
  end

  def history_sql
    count7 = json_integer('$.context.count_7d')
    count30 = json_integer('$.context.count_30d')
    warning = json_integer('$.effective.warning_limit')
    stop = json_integer('$.effective.stop_limit')
    valid = "#{count7} IS NOT NULL AND #{count30} IS NOT NULL AND #{warning} > 0 AND #{stop} >= #{warning}"
    <<~SQL.squish
      SELECT e.id, e.incident_report_id, i.vps_id, i.user_id, v.hostname, u.login AS user_login,
        e.policy_key, e.evaluated_at, i.detected_at, e.matched, e.state, e.snapshot AS _snapshot,
        7 AS warning_period_days, 30 AS stop_period_days, #{count7} AS count_7d, #{count30} AS count_30d,
        #{warning} AS warning_limit, #{stop} AS stop_limit,
        CASE WHEN #{valid} THEN CASE WHEN #{count30} >= #{stop} THEN 'stop_threshold' WHEN #{count7} >= #{warning} THEN 'warning'
          WHEN #{count7} >= CEIL(0.8 * #{warning}) OR #{count30} >= CEIL(0.8 * #{stop}) THEN 'near_limit' ELSE 'clear' END END AS threshold_status,
        CASE WHEN BINARY JSON_UNQUOTE(JSON_EXTRACT(e.snapshot, '$.decision')) IN ('none','warning','stop')
          THEN JSON_UNQUOTE(JSON_EXTRACT(e.snapshot, '$.decision')) ELSE 'none' END AS decision,
        a.id AS action_id, a.kind AS action_kind, a.current_action_state AS action_state,
        a.created_at AS action_created_at, a.updated_at AS action_updated_at, a.transaction_chain_id,
        a.physical_stop_action_id, a.stop_completed_at, a.notice_incident_report_id AS notice_report_id,
        a.current_mail_state AS mail_state, a.mail_queued_at, a.mail_finished_at
      FROM incident_policy_evaluations e JOIN incident_reports i ON i.id = e.incident_report_id
      LEFT JOIN vpses v ON v.id = i.vps_id LEFT JOIN users u ON u.id = i.user_id
      LEFT JOIN action_facts a ON a.incident_policy_evaluation_id = e.id
      WHERE e.evaluated_at <= #{q(@as_of)}
    SQL
  end

  def history_row(row)
    raw = row.delete(:_snapshot)
    snapshot = raw.is_a?(Hash) ? raw : JSON.parse(raw)
    snapshot = {} unless snapshot.is_a?(Hash)
    labels = snapshot['metadata'].is_a?(Hash) && snapshot['metadata']['labels']
    label = labels.is_a?(Hash) && (labels[@language] || labels['en'])
    row[:label] = label.is_a?(String) ? label : row[:policy_key]
    effective = snapshot['effective']
    if effective.is_a?(Hash)
      row[:effective_mode] = effective['mode'] if IncidentEscalation::MODES.include?(effective['mode'])
      if row[:effective_mode] && [true, false].include?(effective['stop_exempt']) && [true, false].include?(effective['suppress_actions'])
        row[:stop_enforced] = effective['mode'] == 'enforce' && !effective['stop_exempt'] && !effective['suppress_actions']
      end
    end
    row
  rescue JSON::ParserError, TypeError
    row.merge(label: row[:policy_key])
  end

  def activity_sql(from, to)
    fields = { stop_completed: 'stop_completed_at', mail_finished: 'mail_finished_at', mail_queued: 'mail_queued_at',
               evaluation: 'evaluated_at', action_updated: 'action_updated_at' }
    times = fields.transform_values { |field| "CASE WHEN #{field} >= #{q(from)} AND #{field} < #{q(to)} THEN #{field} END" }
    times[:action_updated] = "CASE WHEN action_state IN ('failed','uncertain') OR mail_state IN ('failed','uncertain') THEN #{times[:action_updated]} END"
    greatest = "NULLIF(GREATEST(#{times.values.map { |time| "COALESCE(#{time}, '1000-01-01')" }.join(', ')}), '1000-01-01')"
    basis = times.map { |key, time| "WHEN #{time} = #{greatest} THEN #{q(key.to_s)}" }.join(' ')
    "SELECT history.*, #{greatest} AS activity_at, CASE #{basis} END AS activity_basis FROM history"
  end

  def safe_base_url(value)
    uri = URI.parse(value.to_s)
    return unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment

    "#{uri.to_s.sub(%r{/+\z}, '')}/"
  rescue URI::InvalidURIError
    nil
  end

  def link(base, params)
    base && "#{base}?#{URI.encode_www_form(params)}"
  end

  def prepared_links(base, row)
    { vps_url: row[:vps_id] && link(base, page: 'adminvps', action: 'info', veid: row[:vps_id]),
      report_url: row[:incident_report_id] ? link(base, page: 'incidents', action: 'show', id: row[:incident_report_id]) : link(base, page: 'incidents', action: 'list', vps: row[:vps_id]),
      policy_url: row[:vps_id] && link(base, page: 'adminvps', action: 'incidents', veid: row[:vps_id]),
      transaction_url: (row[:transaction_chain_id] || row[:latest_action_chain_id]) && link(base, page: 'transactions', chain: row[:transaction_chain_id] || row[:latest_action_chain_id]) }
  end
end
