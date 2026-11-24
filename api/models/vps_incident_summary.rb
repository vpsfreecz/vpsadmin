# Batched SQL shares the membership/owner boundary used by the engine. Reads
# never invoke applicability selectors or infer membership from codenames.
class VpsIncidentSummary
  def self.accounting_join
    <<~SQL.squish
      LEFT JOIN transaction_chains incident_transfer ON incident_transfer.id = accounting_vps.incident_owner_transfer_chain_id
      LEFT JOIN transactions incident_chown ON incident_chown.transaction_chain_id = incident_transfer.id
        AND incident_transfer.state = 2 AND incident_chown.handle = 3041 AND incident_chown.done = 1
        AND incident_chown.status IN (1, 2)
    SQL
  end

  def self.policy_join(key)
    quoted = Vps.connection.quote(key)
    <<~SQL.squish
      LEFT JOIN vps_incident_policies incident_policy ON incident_policy.vps_id = vpses.id
        AND incident_policy.policy_key = #{quoted}
    SQL
  end

  def self.count_join(now, key, evaluated_before: nil)
    connection = Vps.connection
    quoted_now = connection.quote(now)
    week = connection.quote(now - (7 * IncidentEscalation::DAY))
    month = connection.quote(now - (30 * IncidentEscalation::DAY))
    quoted_key = connection.quote(key)
    <<~SQL.squish
      LEFT JOIN (
        SELECT i.vps_id, SUM(i.detected_at > #{week}) AS count7,
          SUM(i.detected_at > #{month}) AS count30, MAX(i.detected_at) AS last_incident
        FROM incident_reports i JOIN incident_policy_evaluations e ON e.incident_report_id = i.id
          AND e.policy_key = #{quoted_key} AND e.matched = TRUE
          #{"AND e.evaluated_at <= #{connection.quote(evaluated_before)}" if evaluated_before}
        JOIN vpses accounting_vps ON accounting_vps.id = i.vps_id
        #{accounting_join}
        WHERE i.user_id = accounting_vps.user_id AND i.detected_at <= #{quoted_now}
          #{"AND (i.source_kind IS NULL OR i.source_kind != 'incident_policy_notice')" if evaluated_before}
          AND i.detected_at > #{month}
          AND (COALESCE(incident_chown.finished_at, accounting_vps.incident_accounting_since) IS NULL
            OR i.detected_at >= COALESCE(incident_chown.finished_at, accounting_vps.incident_accounting_since))
        GROUP BY i.vps_id
      ) incident_counts ON incident_counts.vps_id = vpses.id
    SQL
  end

  def self.status_sql(key)
    rule = IncidentEscalation.rule(key)
    config = IncidentEscalation.config(policy_key: key)
    warning = "COALESCE(incident_policy.warning_limit_override, #{config[:warning] || rule.warning_limit})"
    stop = "COALESCE(incident_policy.stop_limit_override, #{config[:stop] || rule.stop_limit})"
    <<~SQL.squish
      CASE WHEN #{warning} <= 0 OR #{stop} < #{warning} THEN NULL
        WHEN COALESCE(incident_counts.count30, 0) >= #{stop} THEN 'stop_threshold'
        WHEN COALESCE(incident_counts.count7, 0) >= #{warning} THEN 'warning'
        WHEN COALESCE(incident_counts.count7, 0) >= CEIL(0.8 * #{warning})
          OR COALESCE(incident_counts.count30, 0) >= CEIL(0.8 * #{stop}) THEN 'near_limit'
        ELSE 'clear' END
    SQL
  rescue IncidentEscalation::InvalidConfiguration
    'NULL'
  end

  def self.filter(scope, status, now:, policy_key:)
    IncidentEscalation.rule(policy_key)
    scope.joins(count_join(now, policy_key)).joins(policy_join(policy_key))
         .where("(#{status_sql(policy_key)}) = ?", status)
  end

  def self.registry_row(rule, language: :en)
    { key: rule.key, label: rule.label(language), description: rule.description(language),
      warning_period_days: 7, stop_period_days: 30, settings_category: rule.category }
  end

  def self.policy_rows(vpses, now: Time.now.utc, language: :en)
    rows = vpses.to_a
    result = rows.to_h { |vps| [vps.id, []] }
    return result if rows.empty?

    ids = rows.map(&:id)
    transfers = TransactionChain.where(id: rows.filter_map(&:incident_owner_transfer_chain_id)).includes(:transactions).index_by(&:id)
    reset_warning = rows.to_h do |vps|
      transfer = transfers[vps.incident_owner_transfer_chain_id]
      chown = transfer&.done? && transfer.transactions.any? { |t| t.handle == 3041 && t.done == 'done' && [1, 2].include?(t.status) && t.finished_at }
      [vps.id, chown]
    end
    IncidentEscalation::RULES.each_value do |rule|
      config = IncidentEscalation.config(policy_key: rule.key)
      counts = Vps.unscoped.where(id: ids).joins(count_join(now, rule.key)).joins(policy_join(rule.key)).pluck(
        :id, Arel.sql('COALESCE(incident_counts.count7, 0)'), Arel.sql('COALESCE(incident_counts.count30, 0)'),
        Arel.sql('incident_counts.last_incident'), Arel.sql(status_sql(rule.key))
      ).to_h { |id, *values| [id, values] }
      policies = VpsIncidentPolicy.where(vps_id: ids, policy_key: rule.key).index_by(&:vps_id)
      latest = IncidentPolicyEvaluation.joins(:incident_report)
                                       .joins('JOIN vpses accounting_vps ON accounting_vps.id = incident_reports.vps_id').joins(accounting_join)
                                       .where(policy_key: rule.key, incident_reports: { vps_id: ids })
                                       .where("incident_policy_evaluations.matched = TRUE OR incident_policy_evaluations.state = 'error'")
                                       .where(<<~SQL.squish).group('incident_reports.vps_id').select('MAX(incident_policy_evaluations.id)')
                                         incident_reports.user_id = accounting_vps.user_id
                                         AND (COALESCE(incident_chown.finished_at, accounting_vps.incident_accounting_since) IS NULL
                                           OR incident_reports.detected_at >= COALESCE(incident_chown.finished_at, accounting_vps.incident_accounting_since))
                                       SQL
      evaluations = IncidentPolicyEvaluation.where(id: latest).includes(:incident_report).index_by { |e| e.incident_report.vps_id }
      rows.each do |vps|
        count7, count30, last_incident, status = counts.fetch(vps.id)
        policy = policies[vps.id]
        effective = begin
          IncidentEscalation.new(vps, policy_key: rule.key, now:).effective_result(rule.base, policy:, config:)
        rescue IncidentEscalation::InvalidConfiguration
          nil
        end
        evaluation = evaluations[vps.id]
        result[vps.id] << registry_row(rule, language:).merge(
          count_7d: count7.to_i, count_30d: count30.to_i, configuration_valid: !effective.nil?,
          warning_limit: effective&.fetch('warning_limit'), stop_limit: effective&.fetch('stop_limit'),
          status: effective && status, global_mode: config[:mode], effective_mode: effective&.fetch('mode'),
          stop_enforced: effective && effective['mode'] == 'enforce' && !effective['stop_exempt'] && !effective['suppress_actions'],
          warning_limit_override: policy&.warning_limit_override, stop_limit_override: policy&.stop_limit_override,
          last_incident_at: last_incident, last_warning_at: reset_warning[vps.id] ? nil : policy&.last_warning_at,
          evaluation_report_id: evaluation&.incident_report_id, evaluated_at: evaluation&.evaluated_at,
          evaluation_state: if evaluation
                              evaluation.state == 'error' ? 'error' : 'recorded'
                            else
                              'none'
                            end
        )
      end
    end
    result
  end

  def self.load(vpses, now: Time.now.utc, language: :en)
    rows = vpses.to_a
    return rows if rows.empty?

    summaries = policy_rows(rows, now:, language:)
    transfers = TransactionChain.where(id: rows.filter_map(&:incident_owner_transfer_chain_id)).includes(:transactions).index_by(&:id)
    actions = VpsIncidentAction.outstanding_stops.where(vps_id: rows.map(&:id), stop_owner_action_id: nil)
                               .includes(transaction_chain: :transactions).order(:id).to_a.group_by(&:vps_id)
    rows.each do |vps|
      transfer = transfers[vps.incident_owner_transfer_chain_id]
      chown = transfer.transactions.find { |t| t.handle == 3041 && t.done == 'done' && [1, 2].include?(t.status) } if transfer&.done?
      action = actions[vps.id]&.last
      last_stop = vps[:incident_last_stop_at]
      if action&.transaction_chain&.done?
        stop = action.transaction_chain.transactions.find { |t| t.handle == 1002 && t.done == 'done' && [1, 2].include?(t.status) }
        if stop&.finished_at
          last_stop = [last_stop, stop.finished_at].compact.max
          action = nil
        end
      end
      policies = summaries.fetch(vps.id)
      vps.incident_summary = {
        incident_enforcement_enabled: vps.incident_enforcement_enabled,
        incident_warning_count: policies.count { |p| p[:status] == 'warning' },
        incident_stop_threshold_count: policies.count { |p| p[:status] == 'stop_threshold' },
        incident_last_stop_at: last_stop, incident_next_stop_allowed_at: last_stop && (last_stop + IncidentEscalation::DAY),
        incident_action_state: action ? action_state(action) : 'none', incident_action_chain_id: action&.transaction_chain_id,
        incident_accounting_since: chown&.finished_at || vps[:incident_accounting_since]
      }
    end
    rows
  end

  def self.action_state(action)
    return action.state if %w[failed uncertain].include?(action.state)
    return 'uncertain' if action.transaction_chain && %w[fatal resolved].include?(action.transaction_chain.state)
    return 'failed' if action.transaction_chain&.failed?

    'pending'
  end
end
