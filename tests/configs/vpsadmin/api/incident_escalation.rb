IncidentEscalation.configure do
  rule :oomd do
    labels en: 'VPS memory-pressure incidents', cs: 'Incidenty přetížení paměti VPS'
    limits warning: 5, stop: 10
    templates warning: :vps_memory_pressure_warning, stopped: :vps_memory_pressure_stopped
    applies_if do |ctx|
      ctx.report[:codename] == 'oomd' && ctx.source[:kind] == 'node_vps_event' &&
        !ctx.source[:key].nil? && !ctx.source[:node_id].nil? &&
        ctx.source[:node_id] == ctx.vps[:node_id] && %w[restart stop].include?(ctx.source[:action])
    end
  end

  rule :rtnl_latency do
    labels en: 'RTNL latency incidents', cs: 'Incidenty latence RTNL'
    limits warning: 3, stop: 10
    templates warning: :vps_incident_warning, stopped: :vps_incident_stopped
    applies_if do |ctx|
      ctx.report[:codename] == 'rtnl_latency' && ctx.source[:kind] == 'node_oomd_evidence' &&
        !ctx.source[:key].nil? && !ctx.source[:node_id].nil? &&
        ctx.source[:node_id] == ctx.vps[:node_id] && ctx.source[:action] == 'none'
    end
  end

  rule :manual_category do
    labels en: 'Manual category'
    limits warning: 3, stop: 8
    applies_if { |ctx| ctx.report[:codename] == 'fixture_abuse' }
  end

  rule :manual_content do
    labels en: 'Manual content'
    limits warning: 2, stop: 5
    applies_if { |ctx| ctx.report[:codename] == 'fixture_abuse' && ctx.report[:text].include?('fixture evidence') }
  end
end
