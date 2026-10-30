# Shared SQL makes filtering, pagination totals and displayed counts agree.
class VpsIncidentSummary
  def self.accounting_join
    <<~SQL.squish
      LEFT JOIN transaction_chains incident_transfer ON incident_transfer.id = accounting_vps.incident_owner_transfer_chain_id
      LEFT JOIN transactions incident_chown ON incident_chown.transaction_chain_id = incident_transfer.id
        AND incident_transfer.state = 2 AND incident_chown.handle = 3041 AND incident_chown.done = 1
        AND incident_chown.status IN (1, 2)
    SQL
  end

  def self.policy_join(type)
    quoted = Vps.connection.quote(type)
    <<~SQL.squish
      LEFT JOIN vps_incident_policies incident_policy ON incident_policy.vps_id = vpses.id
        AND incident_policy.incident_type = #{quoted}
    SQL
  end

  def self.count_join(now, type)
    connection = Vps.connection
    quoted_now = connection.quote(now)
    week = connection.quote(now - (7 * IncidentEscalation::DAY))
    month = connection.quote(now - (30 * IncidentEscalation::DAY))
    qualified = IncidentEscalation.rule(type).reports.select(:id).to_sql
    <<~SQL.squish
      LEFT JOIN (
        SELECT i.vps_id, SUM(i.detected_at > #{week}) AS count7,
          SUM(i.detected_at > #{month}) AS count30, MAX(i.detected_at) AS last_incident
        FROM incident_reports i JOIN vpses accounting_vps ON accounting_vps.id = i.vps_id
        #{accounting_join}
        WHERE i.id IN (#{qualified}) AND i.user_id = accounting_vps.user_id
          AND i.detected_at <= #{quoted_now}
          AND (COALESCE(incident_chown.finished_at, accounting_vps.incident_accounting_since) IS NULL
            OR i.detected_at >= COALESCE(incident_chown.finished_at, accounting_vps.incident_accounting_since))
        GROUP BY i.vps_id
      ) incident_counts ON incident_counts.vps_id = vpses.id
    SQL
  end

  def self.status_sql(config)
    warning = "COALESCE(incident_policy.warning_limit_override, #{config[:warning]})"
    stop = "COALESCE(incident_policy.stop_limit_override, #{config[:stop]})"
    <<~SQL.squish
      CASE WHEN COALESCE(incident_counts.count30, 0) >= #{stop} THEN 'stop_threshold'
        WHEN COALESCE(incident_counts.count7, 0) >= #{warning} THEN 'warning'
        WHEN COALESCE(incident_counts.count7, 0) >= CEIL(0.8 * #{warning})
          OR COALESCE(incident_counts.count30, 0) >= CEIL(0.8 * #{stop}) THEN 'near_limit'
        ELSE 'clear' END
    SQL
  end

  def self.filter(scope, status, now:, incident_type: 'oomd')
    config = IncidentEscalation.config(incident_type:)
    scope.joins(count_join(now, incident_type)).joins(policy_join(incident_type))
         .where("(#{status_sql(config)}) = ?", status)
  end

  def self.load(vpses, now: Time.now.utc, incident_type: 'oomd', language: :en)
    rows = vpses.to_a
    rows.each { |vps| vps.incident_summary = nil }
    return rows if rows.empty?

    rule = IncidentEscalation.rule(incident_type)
    config = IncidentEscalation.config(incident_type:)
    counts = Vps.unscoped.where(id: rows.map(&:id)).joins(count_join(now, incident_type))
                .joins(policy_join(incident_type)).pluck(
                  :id, Arel.sql('COALESCE(incident_counts.count7, 0)'), Arel.sql('COALESCE(incident_counts.count30, 0)'),
                  Arel.sql('incident_counts.last_incident'), Arel.sql(status_sql(config)),
                  Arel.sql('incident_policy.warning_limit_override'), Arel.sql('incident_policy.stop_limit_override'),
                  Arel.sql('incident_policy.last_warning_at')
                ).to_h { |id, *values| [id, values] }
    transfers = TransactionChain.where(id: rows.filter_map(&:incident_owner_transfer_chain_id)).includes(:transactions).index_by(&:id)
    actions = VpsIncidentAction.outstanding_stops.where(vps_id: rows.map(&:id)).includes(transaction_chain: :transactions)
                               .order(:id).to_a.group_by(&:vps_id)
    rows.each do |vps|
      count7, count30, last_incident, status, warning, stop_limit, last_warning = counts.fetch(vps.id)
      transfer = transfers[vps.incident_owner_transfer_chain_id]
      chown = if transfer&.done?
                transfer.transactions.find { |t| t.handle == 3041 && t.done == 'done' && [1, 2].include?(t.status) }
              end
      epoch = chown&.finished_at || vps[:incident_accounting_since]
      action = actions[vps.id]&.last
      last_stop = vps[:incident_last_stop_at]
      if action&.transaction_chain&.done?
        stop = action.transaction_chain.transactions.find { |t| t.handle == 1002 && t.done == 'done' && [1, 2].include?(t.status) }
        if stop&.finished_at
          last_stop = [last_stop, stop.finished_at].compact.max
          action = nil
        end
      end
      vps.incident_summary = {
        incident_policy: rule.key, incident_policy_label: rule.label(language),
        incident_count_7d: count7.to_i, incident_count_30d: count30.to_i,
        incident_warning_limit_override: warning, incident_stop_limit_override: stop_limit,
        incident_warning_limit: warning || config[:warning], incident_stop_limit: stop_limit || config[:stop],
        incident_enforcement_enabled: vps.incident_enforcement_enabled,
        incident_mode: config[:mode], incident_stop_enforced: config[:mode] == 'enforce' && vps.incident_enforcement_enabled,
        incident_status: status, incident_last_incident_at: last_incident,
        incident_last_warning_at: chown ? nil : last_warning,
        incident_last_stop_at: last_stop, incident_next_stop_allowed_at: last_stop && (last_stop + IncidentEscalation::DAY),
        incident_action_state: action ? action_state(action) : 'none', incident_action_chain_id: action&.transaction_chain_id,
        incident_accounting_since: epoch
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
