require 'json'
require 'time'

# One authorized SQL snapshot supplies totals, page, ownership, proof and status.
# It never changes a receipt, reconciles ownership, prunes or evaluates reports.
class VpsEvidenceReadProjection
  DATE_FIELDS = %i[window_from window_to last_incident_at last_observed_at].freeze

  attr_reader :read_at

  def initialize(user:, now: Time.now.utc, language: :en)
    @user = user
    @read_at = now.utc
    @language = language.to_s
    settings = SysConfig.where(category: VpsEvidence.categories).to_a.group_by(&:category)
    @configs = VpsEvidence::SIGNALS.to_h do |signal, handler|
      values = settings.fetch(handler::CATEGORY, []).to_h { |row| [row.name.to_sym, row.value] }
      config = begin
        VpsEvidence.config(signal, values)
      rescue ArgumentError
        nil
      end
      [signal, config]
    end
  end

  def for_vps(id)
    result = collection(vps_id: id, positive: false, offset: 0, limit: VpsEvidence::SIGNALS.length)
    raise ActiveRecord::RecordNotFound if result[:rows].empty?

    result[:meta] = result[:meta].slice(:read_at, :configuration_valid, :unavailable_signals)
    result
  end

  def positive(vps_id: nil, user_id: nil, node_id: nil, location_id: nil, environment_id: nil, signal: nil, offset: 0, limit: 25)
    raise ArgumentError, 'Invalid evidence page' unless offset.is_a?(Integer) && offset >= 0 && limit.is_a?(Integer) && limit.between?(1, 100)

    VpsEvidence.definition(signal) if signal
    collection(vps_id:, user_id:, node_id:, location_id:, environment_id:, signal:, positive: true, offset:, limit:)
  end

  protected

  def q(value) = Vps.connection.quote(value)

  def collection(vps_id:, positive:, offset:, limit:, signal: nil, user_id: nil, node_id: nil, location_id: nil, environment_id: nil)
    selected = VpsEvidence::SIGNALS.keys.select { |key| !signal || signal == key }.sort
    unavailable = selected.reject { |key| @configs[key] }
    filters = ["v.object_state IN (#{%i[active suspended soft_delete].map { |state| q(Vps.object_states[state]) }.join(',')})"]
    filters << "v.user_id = #{q(@user.id)}" unless @user.role == :admin
    filters << "v.id = #{q(vps_id)}" if vps_id
    filters << "v.user_id = #{q(user_id)}" if user_id
    filters << "v.node_id = #{q(node_id)}" if node_id
    filters << "n.location_id = #{q(location_id)}" if location_id
    filters << "l.environment_id = #{q(environment_id)}" if environment_id
    authorized = <<~SQL
      SELECT v.id AS vps_id, v.user_id, v.node_id, v.hostname, v.incident_accounting_since AS accounting_since,
        v.incident_owner_transfer_chain_id IS NOT NULL AS transfer_pending,
        v.object_state = #{q(Vps.object_states[:active])} AS vps_active, u.object_state = #{q(User.object_states[:active])} AS owner_active,
        u.login AS user_login, CONCAT(n.name, '.', l.domain) AS node_name, SUBSTRING_INDEX(p.filesystem, '/', 1) AS pool_name,
        cs.status AS status_ok, cs.is_running AS status_running, cs.updated_at AS status_updated_at
      FROM vpses v JOIN users u ON u.id = v.user_id
      LEFT JOIN nodes n ON n.id = v.node_id
      LEFT JOIN locations l ON l.id = n.location_id
      LEFT JOIN dataset_in_pools dip ON dip.id = v.dataset_in_pool_id
      LEFT JOIN pools p ON p.id = dip.pool_id
      LEFT JOIN vps_current_statuses cs ON cs.vps_id = v.id WHERE #{filters.join(' AND ')}
    SQL
    aggregates = selected.filter_map do |key|
      config = @configs[key]
      next unless config

      first = read_at - config[:window_seconds]
      last = read_at
      compatible = 'COUNT(DISTINCT i.measurement) = 1 AND COUNT(DISTINCT i.peak_unit) = 1'
      <<~SQL
        SELECT i.vps_id, #{q(key)} AS `signal`,
          SUM(TIMESTAMPDIFF(MICROSECOND, GREATEST(i.from_at, #{q(first)}), LEAST(i.to_at, #{q(last)}))) AS credit_us,
          CASE WHEN #{compatible} THEN MIN(i.measurement) END AS measurement,
          CASE WHEN #{compatible} THEN MIN(i.peak_unit) END AS peak_unit,
          CASE WHEN #{compatible} THEN MAX(i.peak_value) END AS peak_value,
          CASE WHEN #{compatible} THEN MAX(i.peak_is_lower_bound) END AS peak_is_lower_bound
        FROM vps_evidence_intervals i JOIN authorized v ON v.vps_id = i.vps_id
          AND i.user_id = v.user_id AND i.accounting_since <=> v.accounting_since
        WHERE i.signal = #{q(key)} AND i.incident_report_id IS NULL
          AND i.to_at > #{q(first)} AND i.from_at < #{q(last)} GROUP BY i.vps_id
      SQL
    end
    aggregates << 'SELECT NULL AS vps_id, NULL AS `signal`, NULL AS credit_us, NULL AS measurement, NULL AS peak_unit, NULL AS peak_value, NULL AS peak_is_lower_bound WHERE FALSE' if aggregates.empty?
    pairs = selected.map do |key|
      <<~SQL
        SELECT v.*, #{q(key)} AS `signal`, #{@configs[key] ? 'TRUE' : 'FALSE'} AS configuration_valid,
          COALESCE(a.credit_us, 0) AS credit_us, a.measurement, a.peak_unit, a.peak_value, a.peak_is_lower_bound,
          s.id AS state_id, s.user_id AS state_user_id, s.accounting_since AS state_accounting_since,
          s.node_id AS state_node_id, s.observed_at, s.target, s.complete_since, s.last_incident_at, s.accepted_us
        FROM authorized v LEFT JOIN aggregate_credit a ON a.vps_id = v.vps_id AND a.signal = #{q(key)}
        LEFT JOIN vps_evidence_states s ON s.vps_id = v.vps_id AND s.signal = #{q(key)}
      SQL
    end
    where = positive ? 'configuration_valid AND credit_us > 0 AND NOT transfer_pending AND (state_id IS NULL OR (state_user_id = user_id AND state_accounting_since <=> accounting_since))' : 'TRUE'
    order = 'BINARY `signal` ASC, credit_us DESC, vps_id ASC'
    sql = <<~SQL
      WITH authorized AS (#{authorized}), aggregate_credit AS (#{aggregates.join(' UNION ALL ')}),
      pairs AS (#{pairs.join(' UNION ALL ')}), filtered AS (SELECT * FROM pairs WHERE #{where}),
      page AS (SELECT * FROM filtered ORDER BY #{order} LIMIT #{limit} OFFSET #{offset})
      SELECT page.*, totals.total_count FROM (SELECT COUNT(*) AS total_count FROM filtered) totals
      LEFT JOIN page ON TRUE ORDER BY #{order}
    SQL
    raw = Vps.connection.select_all(sql).to_a
    total = raw.first.fetch('total_count').to_i
    rows = raw.filter_map { |row| row['vps_id'] && project(row) }
    { rows:, meta: { total_count: total, offset:, limit:, next_offset: offset + rows.length < total ? offset + rows.length : nil,
                     read_at:, configuration_valid: unavailable.empty?, unavailable_signals: unavailable } }
  end

  def boolean(value) = [true, 1, '1'].include?(value)

  def time(value)
    return if value.nil?

    value.is_a?(String) ? Time.parse("#{value} UTC").utc : value.to_time.utc
  end

  def project(raw)
    signal = raw.fetch('signal')
    handler = VpsEvidence.definition(signal)
    config = @configs[signal]
    target = raw['target'].is_a?(String) ? JSON.parse(raw['target']) : raw['target']
    facts = raw.symbolize_keys
    %i[user_id node_id state_user_id state_node_id].each { |key| facts[key] = facts[key]&.to_i }
    %i[accounting_since state_accounting_since observed_at complete_since last_incident_at status_updated_at].each { |key| facts[key] = time(facts[key]) }
    %i[transfer_pending vps_active owner_active status_ok status_running].each { |key| facts[key] = boolean(facts[key]) }
    facts.merge!(target:, credit_us: raw.fetch('credit_us').to_i)
    mismatch = !raw['state_id'].nil? && (facts[:state_user_id] != facts[:user_id] || facts[:state_accounting_since] != facts[:accounting_since])
    unavailable = facts[:transfer_pending] || mismatch
    result = config && VpsEvidence.project(facts, now: read_at, settings: config)
    observed = !unavailable && time(raw['observed_at'])
    state = if observed
              observed.between?(read_at - (config || handler::DEFAULTS)[:freshness_seconds], read_at + 2) ? 'fresh' : 'stale'
            else
              'no_data'
            end
    condition = handler.const_defined?(:CONDITION) ? handler::CONDITION : nil
    row = { id: "#{raw['vps_id']}:#{signal}", vps_id: raw['vps_id'].to_i, hostname: raw['hostname'],
            user_id: raw['user_id'].to_i, user_login: raw['user_login'], node_id: raw['node_id']&.to_i, node_name: raw['node_name'],
            signal:, label: handler::LABELS.fetch(@language, handler::LABELS.fetch('en')), representation: handler::REPRESENTATION,
            configuration_valid: !config.nil?, credit_us: config && !unavailable ? facts[:credit_us] : nil,
            window_from: config && (read_at - config[:window_seconds]), window_to: config && read_at,
            window_seconds: config && config[:window_seconds], threshold_seconds: config && config[:threshold_seconds],
            repeat_seconds: config && config[:repeat_seconds], reporting_enabled: config && config[:enabled],
            last_incident_at: (!unavailable && time(raw['last_incident_at'])) || nil, last_observed_at: observed || nil,
            observation_age_seconds: observed ? [(read_at - observed).to_f, 0].max : nil, observation_state: state,
            qualification: (!unavailable && target && target['qualification']) || nil,
            report_eligible: if config && !unavailable
                               result[:fresh]
                             else
                               (config ? false : nil)
                             end,
            report_due: if config && !unavailable
                          result[:report_due]
                        else
                          (config ? false : nil)
                        end,
            window_complete: if config && !unavailable
                               result[:window_complete]
                             else
                               (config ? false : nil)
                             end,
            measurement: nil, peak_unit: nil, peak_value: nil, peak_is_lower_bound: nil }
    unless unavailable || !config || raw['measurement'].nil?
      row.merge!(measurement: raw['measurement'], peak_unit: raw['peak_unit'], peak_value: raw['peak_value']&.to_i,
                 peak_is_lower_bound: raw['peak_is_lower_bound'].nil? ? nil : boolean(raw['peak_is_lower_bound']))
    end
    %w[measurement operator value unit].each { |key| row[:"condition_#{key}"] = condition && condition[key] }
    row
  end
end
