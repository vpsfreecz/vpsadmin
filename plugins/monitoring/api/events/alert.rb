module VpsAdmin::API::Plugins::Monitoring::Events
  module_function

  def event_type_for(alert, variant, alert_kind)
    return 'monitoring.zombie_processes_restart' if alert_kind.to_s == 'restart'

    variant_name = variant.to_sym
    if variant_name == :role_event_state &&
       alert.monitor_name.to_s == 'dns_secondary_transfer_failure'
      return 'monitoring.dns_secondary_transfer_failed'
    end

    VARIANT_EVENT_TYPES.fetch(variant_name) do
      raise ArgumentError, "unknown monitoring alert variant #{variant_name.inspect}"
    end
  end

  def alert_subject(alert, kind)
    state_label = alert.state == 'closed' ? 'resolved' : 'detected'
    kind_label = kind == 'restart' ? 'restart planned' : state_label
    "Monitoring #{kind_label}: #{alert.label}"[0, 255]
  end

  def alert_severity(alert, kind)
    if kind == 'restart'
      'critical'
    elsif alert.state == 'closed'
      'info'
    else
      'warning'
    end
  end

  def related_vps(object)
    return unless object
    return object if defined?(::Vps) && object.is_a?(::Vps)
    return object.vps if object.respond_to?(:vps) && object.vps

    if object.respond_to?(:dataset_expansion)
      expansion = object.dataset_expansion
      return expansion.vps if expansion.respond_to?(:vps)
    end

    nil
  end

  def vps_for(object, owner)
    related = related_vps(object)
    return if owner.nil? || related.nil? || related.user_id != owner.id

    related
  end

  def object_label(alert, object)
    return "#{alert.class_name} ##{alert.row_id}" unless object

    %i[hostname full_name name label].each do |method|
      value = object.public_send(method) if object.respond_to?(method)
      return value.to_s if value.present?
    end

    "#{object.class.name} ##{object.id}"
  end

  def dns_zone(object)
    object.dns_zone if object.respond_to?(:dns_zone)
  end

  def dns_server(object)
    object.dns_server if object.respond_to?(:dns_server)
  end

  def transfer_value(object, method)
    object.public_send(method) if object.respond_to?(method)
  end

  def duration_seconds(alert)
    return if alert.created_at.nil? || alert.updated_at.nil?

    (alert.updated_at - alert.created_at).to_i
  end

  def context_value(context, key)
    context.fetch(key) { context.fetch(key.to_s, nil) }
  end

  def template_state(alert)
    alert.state == 'acknowledged' ? 'confirmed' : alert.state
  end

  def message_id(alert, alert_id, state)
    format(
      ::SysConfig.get(:plugin_monitoring, :alert_message_id),
      event_id: alert.id,
      alert_id:,
      state:
    )
  end

  def mail_thread_options(alert)
    if alert.state == 'closed'
      reply_to = message_id(alert, alert.prev_alert_id, 'confirmed')
      {
        message_id: message_id(alert, alert.next_alert_id, alert.state),
        in_reply_to: reply_to,
        references: reply_to
      }
    else
      {
        message_id: message_id(alert, alert.next_alert_id, 'confirmed')
      }
    end
  end

  def template_params(profile, alert, role, context)
    callable = profile[:template_params]
    callable&.call(alert, role, context)
  end

  def template_options(profile, alert, context)
    ret = { include_template_recipients: false }
    ret.merge!(mail_thread_options(alert)) if profile[:mail_thread]

    language = context_value(context, :language)
    ret[:language] = language if language
    ret
  end

  def template_vars(profile, alert, user, context)
    base_vars = {
      event: alert,
      object: alert.object,
      user:,
      base_url: VpsAdmin::API::Events.webui_url
    }

    callable = profile[:vars]
    callable ? callable.call(base_vars, alert, context) : base_vars
  end

  def field?(profile, field)
    profile.fetch(:fields, []).include?(field)
  end

  VARIANT_EVENT_TYPES = {
    role_event_state: 'monitoring.monitor_state_changed',
    role_diskspace_state_pool: 'monitoring.diskspace_low',
    zombie_processes_state: 'monitoring.zombie_processes',
    zombie_processes_restart: 'monitoring.zombie_processes_restart',
    vps_in_rescue: 'monitoring.vps_in_rescue',
    dataset_over_quota: 'monitoring.dataset_over_quota'
  }.freeze

  EVENT_PROFILES = {
    'monitoring.monitor_state_changed' => {
      variant: :role_event_state,
      label: 'Monitoring state changed',
      template: :alert_role_event_state,
      fields: %i[vps],
      mail_thread: true,
      template_params: lambda do |alert, role, _context|
        {
          role: role.to_sym,
          event: alert.monitor_definition&.name || alert.monitor_name,
          state: VpsAdmin::API::Plugins::Monitoring::Events.template_state(alert)
        }
      end
    },
    'monitoring.diskspace_low' => {
      variant: :role_diskspace_state_pool,
      label: 'Disk space low',
      template: :alert_role_diskspace_state_pool,
      fields: %i[vps dataset pool_role],
      mail_thread: true,
      template_params: lambda do |alert, role, context|
        {
          role: role.to_sym,
          state: VpsAdmin::API::Plugins::Monitoring::Events.template_state(alert),
          pool: VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :pool_role)
        }
      end,
      vars: lambda do |base, alert, context|
        base.merge(
          dip: VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :dip),
          ds: alert.object,
          vps: VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :vps)
        )
      end
    },
    'monitoring.zombie_processes' => {
      variant: :zombie_processes_state,
      label: 'Zombie processes detected',
      template: :alert_user_zombie_processes_state,
      fields: %i[vps threshold],
      mail_thread: true,
      template_params: lambda do |alert, _role, _context|
        {
          state: VpsAdmin::API::Plugins::Monitoring::Events.template_state(alert)
        }
      end,
      vars: lambda do |base, alert, context|
        vps = VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :vps) ||
              alert.object
        base.merge(
          vps:,
          zombie_process_count: vps.zombie_process_count,
          threshold: VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :threshold)
        )
      end
    },
    'monitoring.zombie_processes_restart' => {
      variant: :zombie_processes_restart,
      label: 'Zombie processes restart planned',
      template: :alert_user_zombie_processes_restart,
      fields: %i[vps threshold maintenance],
      vars: lambda do |base, alert, context|
        vps = VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :vps) ||
              alert.object
        base.merge(
          vps:,
          zombie_process_count: vps.zombie_process_count,
          threshold: VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :threshold),
          finish_weekday: VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :finish_weekday),
          finish_minutes: VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :finish_minutes)
        )
      end
    },
    'monitoring.vps_in_rescue' => {
      variant: :vps_in_rescue,
      label: 'VPS in rescue mode',
      template: :alert_user_vps_in_rescue,
      fields: %i[vps],
      vars: lambda do |base, alert, _context|
        base.merge(vps: alert.object)
      end
    },
    'monitoring.dataset_over_quota' => {
      variant: :dataset_over_quota,
      label: 'Dataset over quota',
      template: :alert_vps_dataset_over_quota,
      fields: %i[vps dataset],
      vars: lambda do |base, alert, _context|
        expansion = alert.object.dataset_expansion
        base.merge(
          dataset: alert.object,
          expansion:,
          vps: expansion.vps
        )
      end
    },
    'monitoring.dns_secondary_transfer_failed' => {
      variant: :role_event_state,
      label: 'DNS secondary transfer failed',
      template: :alert_role_event_state,
      fields: %i[dns],
      mail_thread: true,
      template_params: lambda do |alert, role, _context|
        {
          role: role.to_sym,
          event: alert.monitor_definition&.name || alert.monitor_name,
          state: VpsAdmin::API::Plugins::Monitoring::Events.template_state(alert)
        }
      end
    }
  }.freeze
end

VpsAdmin::API::Events.define owner: :monitoring do
  VpsAdmin::API::Plugins::Monitoring::Events::EVENT_PROFILES.each do |event_name, profile|
    event event_name,
          label: profile.fetch(:label),
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
      argument :variant, type: [String, Symbol], default: profile.fetch(:variant)
      argument :context, type: Hash, default: {}

      user { recipient || alert.user }
      source { alert }
      vps do
        VpsAdmin::API::Plugins::Monitoring::Events.vps_for(
          alert.object,
          recipient || alert.user
        )
      end
      subject do
        subject_override ||
          VpsAdmin::API::Plugins::Monitoring::Events.alert_subject(alert, alert_kind)
      end
      summary do
        summary_override ||
          alert.issue.to_s.truncate(::Event::MAX_SUMMARY_LENGTH)
      end
      severity do
        severity_override&.to_s ||
          VpsAdmin::API::Plugins::Monitoring::Events.alert_severity(alert, alert_kind)
      end

      parameter(:role, 'Recipient role') { role }
      parameter(:alert_kind, 'Monitoring alert kind') { alert_kind }
      parameter(:variant, 'Monitoring alert variant') { variant.to_s }
      parameter(:monitor_name, 'Monitor internal name') { alert.monitor_name }
      parameter(:monitor_label, 'Monitor label') { alert.label }
      parameter(:monitor_issue, 'Monitor issue description') { alert.issue }
      parameter(:monitored_event_id, 'Monitored event ID') { alert.id }
      parameter(:state, 'Monitored event state') { alert.state }
      parameter(:object_class, 'Monitored object class') { alert.class_name }
      parameter(:object_id, 'Monitored object ID') { alert.row_id }
      parameter(:object_label, 'Monitored object label') do
        VpsAdmin::API::Plugins::Monitoring::Events.object_label(alert, alert.object)
      end
      parameter(:measured_value, 'Latest measured value') do
        alert.monitored_event_logs.order(:id).last&.value
      end
      parameter(:check_count, 'Number of recorded checks') { alert.check_count }
      parameter(:alert_number, 'Alert sequence number') { alert.next_alert_id }
      parameter(:affected_user_id, 'Affected user ID') { alert.user_id }
      parameter(:affected_user_login, 'Affected user login') { alert.user&.login }

      if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :vps)
        parameter(:vps_id, 'Affected VPS ID') do
          VpsAdmin::API::Plugins::Monitoring::Events.related_vps(alert.object)&.id
        end
        parameter(:vps_hostname, 'Affected VPS hostname') do
          VpsAdmin::API::Plugins::Monitoring::Events.related_vps(alert.object)&.hostname
        end
      end

      if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :dataset)
        parameter(:dataset_id, 'Affected dataset ID') do
          alert.object.id if defined?(::Dataset) && alert.object.is_a?(::Dataset)
        end
        parameter(:dataset_full_name, 'Affected dataset name') do
          alert.object.full_name if defined?(::Dataset) && alert.object.is_a?(::Dataset)
        end
      end

      if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :dns)
        parameter(:dns_zone_id, 'Affected DNS zone ID') do
          VpsAdmin::API::Plugins::Monitoring::Events.dns_zone(alert.object)&.id
        end
        parameter(:dns_zone_name, 'Affected DNS zone name') do
          VpsAdmin::API::Plugins::Monitoring::Events.dns_zone(alert.object)&.name
        end
        parameter(:dns_server_id, 'DNS server ID') do
          VpsAdmin::API::Plugins::Monitoring::Events.dns_server(alert.object)&.id
        end
        parameter(:dns_server_name, 'DNS server name') do
          VpsAdmin::API::Plugins::Monitoring::Events.dns_server(alert.object)&.name
        end
        parameter(:transfer_status, 'DNS zone transfer status') do
          VpsAdmin::API::Plugins::Monitoring::Events.transfer_value(
            alert.object,
            :last_transfer_status
          )
        end
        parameter(:transfer_reason_code, 'DNS transfer reason code') do
          VpsAdmin::API::Plugins::Monitoring::Events.transfer_value(
            alert.object,
            :last_transfer_reason_code
          )
        end
        parameter(:transfer_reason, 'DNS transfer reason') do
          VpsAdmin::API::Plugins::Monitoring::Events.transfer_value(
            alert.object,
            :last_transfer_reason
          )
        end
      end

      if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :pool_role)
        parameter(:pool_role, 'Storage pool role') do
          VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :pool_role)
        end
      end

      if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :threshold)
        parameter(:threshold, 'Alert threshold') do
          VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :threshold)
        end
      end

      if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :maintenance)
        parameter(:finish_weekday, 'Maintenance window weekday') do
          VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :finish_weekday)
        end
        parameter(:finish_minutes, 'Maintenance window finish minute') do
          VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :finish_minutes)
        end
      end

      parameter(:created_at, 'Monitored event creation time') { alert.created_at&.iso8601 }
      parameter(:updated_at, 'Monitored event update time') { alert.updated_at&.iso8601 }
      parameter(:last_report_at, 'Last report time') { alert.last_report_at&.iso8601 }
      parameter(:saved_until, 'Acknowledged or ignored until') { alert.saved_until&.iso8601 }
      parameter(:duration_seconds, 'Monitored event duration in seconds') do
        VpsAdmin::API::Plugins::Monitoring::Events.duration_seconds(alert)
      end
      extra_parameters { extra_parameters }

      deliver :email do
        template profile.fetch(:template)
        params do
          VpsAdmin::API::Plugins::Monitoring::Events.template_params(
            profile,
            alert,
            role,
            context
          )
        end
        options do
          VpsAdmin::API::Plugins::Monitoring::Events.template_options(
            profile,
            alert,
            context
          )
        end
        vars do
          VpsAdmin::API::Plugins::Monitoring::Events.template_vars(
            profile,
            alert,
            recipient || alert.user,
            context
          )
        end
      end
    end
  end
end
