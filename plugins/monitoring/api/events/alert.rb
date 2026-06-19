VpsAdmin::API::Events.define owner: :monitoring do
  event 'monitoring.alert',
        label: 'Monitoring alert',
        category: 'monitoring',
        severity: :warning,
        default_routed: true,
        severity_description: 'Severity is derived from the monitoring alert state' do
    argument :alert, type: ::MonitoredEvent
    argument :recipient, type: ::User, optional: true
    argument :role, type: String, default: 'user'
    argument :alert_kind, type: String, default: 'state'
    argument :subject_override, type: String, optional: true
    argument :summary_override, type: String, optional: true
    argument :severity_override, type: [String, Symbol], optional: true
    argument :extra_parameters, type: Hash, default: {}
    argument :variant, type: [String, Symbol], default: :role_event_state
    argument :context, type: Hash, default: {}

    helper :monitoring_alert_subject do |event, kind|
      state_label = event.state == 'closed' ? 'resolved' : 'detected'
      kind_label = kind == 'restart' ? 'restart planned' : state_label
      "Monitoring #{kind_label}: #{event.label}"[0, 255]
    end

    helper :monitoring_alert_severity do |event, kind|
      if kind == 'restart'
        'critical'
      elsif event.state == 'closed'
        'info'
      else
        'warning'
      end
    end

    helper :monitoring_related_vps do |object|
      next unless object
      next object if defined?(::Vps) && object.is_a?(::Vps)
      next object.vps if object.respond_to?(:vps) && object.vps

      if object.respond_to?(:dataset_expansion)
        expansion = object.dataset_expansion
        next expansion.vps if expansion.respond_to?(:vps)
      end

      nil
    end

    helper :monitoring_vps_for do |object, owner|
      related = monitoring_related_vps(object)
      next if owner.nil? || related.nil? || related.user_id != owner.id

      related
    end

    helper :monitoring_object_label do |event, object|
      next "#{event.class_name} ##{event.row_id}" unless object

      %i[hostname full_name name label].each do |method|
        value = object.public_send(method) if object.respond_to?(method)
        next value.to_s if value.present?
      end

      "#{object.class.name} ##{object.id}"
    end

    helper :monitoring_dns_zone do |object|
      object.dns_zone if object.respond_to?(:dns_zone)
    end

    helper :monitoring_dns_server do |object|
      object.dns_server if object.respond_to?(:dns_server)
    end

    helper :monitoring_transfer_value do |object, method|
      object.public_send(method) if object.respond_to?(method)
    end

    helper :monitoring_duration_seconds do |event|
      next if event.created_at.nil? || event.updated_at.nil?

      (event.updated_at - event.created_at).to_i
    end

    helper :monitoring_variant do
      name = variant.to_sym
      monitoring_template_name_for(name)
      name
    end

    helper :monitoring_context_value do |key|
      context.fetch(key) { context.fetch(key.to_s, nil) }
    end

    helper :monitoring_template_state do |event|
      event.state == 'acknowledged' ? 'confirmed' : event.state
    end

    helper :monitoring_message_id do |event, alert_id, state|
      format(
        ::SysConfig.get(:plugin_monitoring, :alert_message_id),
        event_id: event.id,
        alert_id:,
        state:
      )
    end

    helper :monitoring_mail_thread_options do |event|
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

    helper :monitoring_template_name_for do |variant_name|
      {
        role_event_state: :alert_role_event_state,
        role_diskspace_state_pool: :alert_role_diskspace_state_pool,
        zombie_processes_restart: :alert_user_zombie_processes_restart,
        zombie_processes_state: :alert_user_zombie_processes_state,
        vps_in_rescue: :alert_user_vps_in_rescue,
        dataset_over_quota: :alert_vps_dataset_over_quota
      }.fetch(variant_name) do
        raise ArgumentError, "unknown monitoring alert variant #{variant_name.inspect}"
      end
    end

    helper :monitoring_template_params_for do |variant_name, event, role_name|
      case variant_name
      when :role_event_state
        {
          role: role_name.to_sym,
          event: event.monitor_definition&.name || event.monitor_name,
          state: monitoring_template_state(event)
        }
      when :role_diskspace_state_pool
        {
          role: role_name.to_sym,
          state: monitoring_template_state(event),
          pool: monitoring_context_value(:pool_role)
        }
      when :zombie_processes_state
        {
          state: monitoring_template_state(event)
        }
      when :zombie_processes_restart, :vps_in_rescue, :dataset_over_quota
        nil
      else
        monitoring_template_name_for(variant_name)
        nil
      end
    end

    helper :monitoring_template_options_for do |variant_name, event|
      ret = { include_template_recipients: false }
      if %i[
        role_event_state
        role_diskspace_state_pool
        zombie_processes_state
      ].include?(variant_name)
        ret.merge!(monitoring_mail_thread_options(event))
      end
      ret[:language] = monitoring_context_value(:language) if monitoring_context_value(:language)
      ret
    end

    helper :monitoring_template_vars_for do |variant_name, event, user|
      base_vars = {
        event:,
        object: event.object,
        user:,
        base_url: webui_url
      }

      case variant_name
      when :role_event_state
        base_vars
      when :role_diskspace_state_pool
        dip = monitoring_context_value(:dip)
        base_vars.merge(
          dip:,
          ds: event.object,
          vps: monitoring_context_value(:vps)
        )
      when :zombie_processes_restart
        vps = monitoring_context_value(:vps) || event.object
        base_vars.merge(
          vps:,
          zombie_process_count: vps.zombie_process_count,
          threshold: monitoring_context_value(:threshold),
          finish_weekday: monitoring_context_value(:finish_weekday),
          finish_minutes: monitoring_context_value(:finish_minutes)
        )
      when :zombie_processes_state
        vps = monitoring_context_value(:vps) || event.object
        base_vars.merge(
          vps:,
          zombie_process_count: vps.zombie_process_count,
          threshold: monitoring_context_value(:threshold)
        )
      when :vps_in_rescue
        base_vars.merge(vps: event.object)
      when :dataset_over_quota
        expansion = event.object.dataset_expansion
        base_vars.merge(
          dataset: event.object,
          expansion:,
          vps: expansion.vps
        )
      else
        monitoring_template_name_for(variant_name)
        base_vars
      end
    end

    user { recipient || alert.user }
    source { alert }
    vps { monitoring_vps_for(alert.object, recipient || alert.user) }
    subject { subject_override || monitoring_alert_subject(alert, alert_kind) }
    summary { summary_override || alert.issue.to_s.truncate(::Event::MAX_SUMMARY_LENGTH) }
    severity { severity_override&.to_s || monitoring_alert_severity(alert, alert_kind) }

    parameter(:role, 'Recipient role') { role }
    parameter(:alert_kind, 'Monitoring alert kind') { alert_kind }
    parameter(:variant, 'Monitoring alert variant') { monitoring_variant.to_s }
    parameter(:monitor_name, 'Monitor internal name') { alert.monitor_name }
    parameter(:monitor_label, 'Monitor label') { alert.label }
    parameter(:monitor_issue, 'Monitor issue description') { alert.issue }
    parameter(:monitored_event_id, 'Monitored event ID') { alert.id }
    parameter(:state, 'Monitored event state') { alert.state }
    parameter(:object_class, 'Monitored object class') { alert.class_name }
    parameter(:object_id, 'Monitored object ID') { alert.row_id }
    parameter(:object_label, 'Monitored object label') { monitoring_object_label(alert, alert.object) }
    parameter(:measured_value, 'Latest measured value') { alert.monitored_event_logs.order(:id).last&.value }
    parameter(:check_count, 'Number of recorded checks') { alert.check_count }
    parameter(:alert_number, 'Alert sequence number') { alert.next_alert_id }
    parameter(:affected_user_id, 'Affected user ID') { alert.user_id }
    parameter(:affected_user_login, 'Affected user login') { alert.user&.login }
    parameter(:vps_id, 'Affected VPS ID') { monitoring_related_vps(alert.object)&.id }
    parameter(:vps_hostname, 'Affected VPS hostname') { monitoring_related_vps(alert.object)&.hostname }
    parameter(:dataset_id, 'Affected dataset ID') { alert.object.id if defined?(::Dataset) && alert.object.is_a?(::Dataset) }
    parameter(:dataset_full_name, 'Affected dataset name') { alert.object.full_name if defined?(::Dataset) && alert.object.is_a?(::Dataset) }
    parameter(:dns_zone_id, 'Affected DNS zone ID') { monitoring_dns_zone(alert.object)&.id }
    parameter(:dns_zone_name, 'Affected DNS zone name') { monitoring_dns_zone(alert.object)&.name }
    parameter(:dns_server_id, 'DNS server ID') { monitoring_dns_server(alert.object)&.id }
    parameter(:dns_server_name, 'DNS server name') { monitoring_dns_server(alert.object)&.name }
    parameter(:transfer_status, 'DNS zone transfer status') { monitoring_transfer_value(alert.object, :last_transfer_status) }
    parameter(:transfer_reason_code, 'DNS transfer reason code') { monitoring_transfer_value(alert.object, :last_transfer_reason_code) }
    parameter(:transfer_reason, 'DNS transfer reason') { monitoring_transfer_value(alert.object, :last_transfer_reason) }
    parameter(:created_at, 'Monitored event creation time') { alert.created_at&.iso8601 }
    parameter(:updated_at, 'Monitored event update time') { alert.updated_at&.iso8601 }
    parameter(:last_report_at, 'Last report time') { alert.last_report_at&.iso8601 }
    parameter(:saved_until, 'Acknowledged or ignored until') { alert.saved_until&.iso8601 }
    parameter(:duration_seconds, 'Monitored event duration in seconds') { monitoring_duration_seconds(alert) }
    extra_parameters { extra_parameters }

    deliver :email do
      template { monitoring_template_name_for(monitoring_variant) }
      params { monitoring_template_params_for(monitoring_variant, alert, role) }
      options { monitoring_template_options_for(monitoring_variant, alert) }
      vars do
        monitoring_template_vars_for(monitoring_variant, alert, recipient || alert.user)
      end
    end
  end
end
