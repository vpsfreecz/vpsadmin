module VpsAdmin::API::Plugins::Monitoring::TransactionChains
  class Alert < ::TransactionChain
    label 'Alert'
    allow_empty

    def link_chain(event)
      concerns(:affect, [event.object.class.name, event.object.id]) if event.object
      event.call_action(self, event)
      event.increment!(:alert_count) unless empty?
    end

    def route_monitoring_alert!(event, event_type: nil, affected_user: event.user,
                                alert_kind: 'state',
                                context: {}, severity: nil, subject: nil,
                                summary: nil, payload: {})
      event_type ||= VpsAdmin::API::Plugins::Monitoring::Events.event_type_for_monitor(
        event.monitor_name
      )

      route_event!(
        event_type,
        alert: event,
        affected_user: affected_user || event.user,
        alert_kind: alert_kind.to_s,
        context: context || {},
        subject_override: subject,
        summary_override: summary,
        severity_override: severity,
        extra_payload: payload || {}
      )
    end

    def monitoring_admin_recipients
      ::User.existing.where('level >= 90').order(:id)
    end
  end
end
