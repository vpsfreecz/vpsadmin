module VpsAdmin::API::Plugins::Monitoring::TransactionChains
  class Alert < ::TransactionChain
    label 'Alert'
    allow_empty

    def link_chain(event)
      concerns(:affect, [event.object.class.name, event.object.id]) if event.object
      event.call_action(self, event)
      event.increment!(:alert_count) unless empty?
    end

    def route_monitoring_alert!(event, user: event.user, role: 'user',
                                alert_kind: 'state', severity: nil,
                                subject: nil, summary: nil, parameters: {},
                                template_name: nil, template_params: nil,
                                email_vars: {}, email_options: {})
      user ||= event.user
      object = event.object

      route_event!(
        'monitoring.alert',
        user:,
        vps: monitoring_vps_for(object, user),
        source: event,
        subject: subject || monitoring_alert_subject(event, alert_kind),
        summary: summary || monitoring_alert_summary(event),
        severity: severity || monitoring_alert_severity(event, alert_kind),
        parameters: monitoring_alert_parameters(
          event,
          object:,
          role:,
          alert_kind:
        ).merge(parameters || {}).compact,
        email_template_name: template_name,
        email_template_params: template_params,
        email_options: { include_template_recipients: false }.merge(email_options || {}),
        email_vars: monitoring_email_vars(event, user, object).merge(email_vars || {})
      )
    end

    def monitoring_admin_recipients
      ::User.existing.where('level >= 90').order(:id)
    end

    def monitoring_mail_thread_options(event)
      if event.state == 'closed'
        reply_to = monitoring_message_id(event, event.prev_alert_id, 'confirmed')
        {
          message_id: monitoring_message_id(event, event.next_alert_id, event.state),
          in_reply_to: reply_to,
          references: reply_to
        }
      else
        {
          message_id: monitoring_message_id(event, event.next_alert_id, 'confirmed')
        }
      end
    end

    def monitoring_template_state(event)
      event.state == 'acknowledged' ? 'confirmed' : event.state
    end

    protected

    def monitoring_message_id(event, alert_id, state)
      format(
        ::SysConfig.get(:plugin_monitoring, :alert_message_id),
        event_id: event.id,
        alert_id:,
        state:
      )
    end

    def monitoring_alert_subject(event, alert_kind)
      state_label = event.state == 'closed' ? 'resolved' : 'detected'
      kind = alert_kind == 'restart' ? 'restart planned' : state_label
      "Monitoring #{kind}: #{event.label}"[0, 255]
    end

    def monitoring_alert_summary(event)
      event.issue.to_s.truncate(::Event::MAX_SUMMARY_LENGTH)
    end

    def monitoring_alert_severity(event, alert_kind)
      return 'critical' if alert_kind == 'restart'
      return 'info' if event.state == 'closed'

      'warning'
    end

    def monitoring_alert_parameters(event, object:, role:, alert_kind:)
      latest_log = event.monitored_event_logs.order(:id).last

      {
        role:,
        alert_kind:,
        monitor_name: event.monitor_name,
        monitor_label: event.label,
        monitor_issue: event.issue,
        monitored_event_id: event.id,
        state: event.state,
        object_class: event.class_name,
        object_id: event.row_id,
        object_label: monitoring_object_label(event, object),
        measured_value: latest_log&.value,
        check_count: event.check_count,
        alert_number: event.next_alert_id,
        affected_user_id: event.user_id,
        affected_user_login: event.user&.login,
        created_at: event.created_at&.iso8601,
        updated_at: event.updated_at&.iso8601,
        last_report_at: event.last_report_at&.iso8601,
        saved_until: event.saved_until&.iso8601,
        duration_seconds: monitoring_duration_seconds(event)
      }.merge(monitoring_object_parameters(object)).compact
    end

    def monitoring_object_parameters(object)
      return {} unless object

      ret = {}
      vps = monitoring_related_vps(object)
      if vps
        ret[:vps_id] = vps.id
        ret[:vps_hostname] = vps.hostname
      end

      if defined?(::Dataset) && object.is_a?(::Dataset)
        ret[:dataset_id] = object.id
        ret[:dataset_full_name] = object.full_name
      end

      ret.merge!(monitoring_dns_parameters(object))
      ret
    end

    def monitoring_dns_parameters(object)
      return {} unless object.respond_to?(:dns_zone) && object.respond_to?(:dns_server)

      zone = object.dns_zone
      server = object.dns_server
      {
        dns_zone_id: zone&.id,
        dns_zone_name: zone&.name,
        dns_server_id: server&.id,
        dns_server_name: server&.name,
        transfer_status: object.respond_to?(:last_transfer_status) ? object.last_transfer_status : nil,
        transfer_reason_code: object.respond_to?(:last_transfer_reason_code) ? object.last_transfer_reason_code : nil,
        transfer_reason: object.respond_to?(:last_transfer_reason) ? object.last_transfer_reason : nil
      }.compact
    end

    def monitoring_vps_for(object, user)
      vps = monitoring_related_vps(object)
      return if user.nil? || vps.nil? || vps.user_id != user.id

      vps
    end

    def monitoring_related_vps(object)
      return unless object
      return object if defined?(::Vps) && object.is_a?(::Vps)
      return object.vps if object.respond_to?(:vps) && object.vps

      if object.respond_to?(:dataset_expansion)
        expansion = object.dataset_expansion
        return expansion.vps if expansion.respond_to?(:vps)
      end

      nil
    end

    def monitoring_object_label(event, object)
      return "#{event.class_name} ##{event.row_id}" unless object

      %i[hostname full_name name label].each do |method|
        return object.public_send(method).to_s if object.respond_to?(method) && object.public_send(method).present?
      end

      "#{object.class.name} ##{object.id}"
    end

    def monitoring_duration_seconds(event)
      return if event.created_at.nil? || event.updated_at.nil?

      (event.updated_at - event.created_at).to_i
    end

    def monitoring_email_vars(event, user, object)
      {
        event:,
        object:,
        user:,
        base_url: ::SysConfig.get(:webui, :base_url)
      }
    end
  end
end
