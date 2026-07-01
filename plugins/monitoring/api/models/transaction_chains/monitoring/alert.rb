module VpsAdmin::API::Plugins::Monitoring::TransactionChains
  class Alert < ::TransactionChain
    label 'Alert'
    allow_empty

    def link_chain(event)
      concerns(:affect, [event.object.class.name, event.object.id]) if event.object
      event.call_action(self, event)
      event.increment!(:alert_count) unless empty?
    end

    def route_monitoring_alert!(event, recipient: event.user, role: 'user',
                                alert_kind: 'state', variant: :role_event_state,
                                context: {}, severity: nil, subject: nil,
                                summary: nil, payload: {})
      route_event!(
        VpsAdmin::API::Plugins::Monitoring::Events.event_type_for(
          event,
          variant,
          alert_kind
        ),
        alert: event,
        recipient: recipient || event.user,
        role: role.to_s,
        alert_kind: alert_kind.to_s,
        variant:,
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
