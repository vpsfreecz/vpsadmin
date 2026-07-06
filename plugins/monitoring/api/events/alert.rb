module VpsAdmin::API::Plugins::Monitoring::Events
  module_function

  FIELD_DESCRIPTIONS = {
    alert_kind: 'Kind of monitoring alert that produced the notification',
    monitor_name: 'Internal name of the monitor definition',
    monitor_label: 'User-visible monitor label',
    monitor_issue: 'Issue text reported by the monitor',
    monitored_event_id: 'ID of the monitored event row',
    state: 'State of the monitored event after the check',
    object_class: 'Class name of the monitored object',
    object_id: 'ID of the monitored object',
    object_label: 'User-visible label of the monitored object',
    measured_value: 'Latest value recorded by the monitor',
    check_count: 'Number of recorded checks for the monitored event',
    alert_number: 'Sequence number of this alert for the monitored event',
    affected_user_id: 'ID of the user affected by the monitoring event',
    affected_user_login: 'Login of the user affected by the monitoring event',
    vps_id: 'ID of the VPS affected by the monitoring event',
    vps_hostname: 'Hostname of the VPS affected by the monitoring event',
    dataset_id: 'ID of the dataset affected by the monitoring event',
    dataset_full_name: 'Full name of the dataset affected by the monitoring event',
    dns_zone_id: 'ID of the DNS zone affected by the monitoring event',
    dns_zone_name: 'Name of the DNS zone affected by the monitoring event',
    dns_server_id: 'ID of the DNS server involved in the monitoring event',
    dns_server_name: 'Name of the DNS server involved in the monitoring event',
    transfer_status: 'Last DNS zone transfer status observed by monitoring',
    transfer_reason_code: 'Machine-readable reason for the last DNS transfer state',
    transfer_reason: 'Human-readable reason for the last DNS transfer state',
    pool_role: 'Storage pool role associated with the monitoring event',
    threshold: 'Numeric threshold configured for the monitoring alert',
    finish_weekday: 'Weekday when the maintenance window should finish',
    finish_minutes: 'Minute of day when the maintenance window should finish',
    created_at: 'Time when the monitored event was created',
    updated_at: 'Time when the monitored event was last updated',
    last_report_at: 'Time when the monitored event was last reported',
    saved_until: 'Time until which the monitored event is acknowledged or ignored',
    duration_seconds: 'Duration of the monitored event in seconds'
  }.freeze

  def event_profiles
    @event_profiles ||= {}
  end

  def i18n_defaults
    FIELD_DESCRIPTIONS.to_h do |name, description|
      ["events.fields.monitoring.#{name}.description", description]
    end.merge(
      'events.types.monitoring.severity_description' =>
        'Severity is derived from the monitoring alert state'
    )
  end

  def field_description(name)
    FIELD_DESCRIPTIONS.fetch(name.to_sym)
  end

  def monitor_event_types
    @monitor_event_types ||= {}
  end

  def register_event(event_type, label:, template:, monitors: nil, fields: [],
                     default_routed: true, severity: :warning,
                     severity_description: 'Severity is derived from the monitoring alert state',
                     roles: %i[admin], mail_thread: true,
                     template_params: nil, vars: nil)
    event_type_s = event_type.to_s
    profile = {
      event_type: event_type_s,
      label:,
      template:,
      fields: Array(fields).map(&:to_sym),
      default_routed:,
      severity:,
      severity_description:,
      roles:,
      mail_thread:,
      template_params:,
      vars:
    }
    event_profiles[event_type_s] = profile
    Array(monitors).each { |monitor_name| monitor_event_types[monitor_name.to_s] = event_type_s }

    define_event_profile(event_type_s, profile)
  end

  def event_type_for_monitor(monitor_name)
    monitor_event_types.fetch(monitor_name.to_s) do
      raise ArgumentError, "no monitoring event registered for monitor #{monitor_name.inspect}"
    end
  end

  def resolve_template(profile, alert, context)
    value = profile.fetch(:template)
    value.respond_to?(:call) ? value.call(alert, context) : value
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

  def template_params(profile, alert, context)
    callable = profile[:template_params]
    callable&.call(alert, context)
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

  def define_event_profile(event_name, profile)
    descriptions = FIELD_DESCRIPTIONS

    VpsAdmin::API::Events.define owner: :monitoring do
      event event_name,
            label: profile.fetch(:label),
            category: 'monitoring',
            severity: profile.fetch(:severity),
            roles: profile.fetch(:roles),
            default_routed: profile.fetch(:default_routed),
            severity_description: profile.fetch(:severity_description) do
        argument :alert, type: ::MonitoredEvent
        argument :affected_user, type: ::User, optional: true
        argument :alert_kind, type: String, default: 'state'
        argument :subject_override, type: String, optional: true
        argument :summary_override, type: String, optional: true
        argument :severity_override, type: [String, Symbol], optional: true
        argument :extra_payload, type: Hash, default: {}
        argument :context, type: Hash, default: {}

        user { affected_user || alert.user }
        source { alert }
        vps do
          VpsAdmin::API::Plugins::Monitoring::Events.vps_for(
            alert.object,
            affected_user || alert.user
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

        field(:alert_kind, descriptions.fetch(:alert_kind), type: :string) { alert_kind }
        field(:monitor_name, descriptions.fetch(:monitor_name), type: :string) { alert.monitor_name }
        field(:monitor_label, descriptions.fetch(:monitor_label), type: :string) { alert.label }
        field(:monitor_issue, descriptions.fetch(:monitor_issue), type: :string) { alert.issue }
        field(:monitored_event_id, descriptions.fetch(:monitored_event_id), type: :integer) { alert.id }
        field(:state, descriptions.fetch(:state), type: :string) { alert.state }
        field(:object_class, descriptions.fetch(:object_class), type: :string) { alert.class_name }
        field(:object_id, descriptions.fetch(:object_id), type: :integer) { alert.row_id }
        field(:object_label, descriptions.fetch(:object_label), type: :string) do
          VpsAdmin::API::Plugins::Monitoring::Events.object_label(alert, alert.object)
        end
        field(:measured_value, descriptions.fetch(:measured_value), type: :string) do
          alert.monitored_event_logs.order(:id).last&.value
        end
        field(:check_count, descriptions.fetch(:check_count), type: :integer) { alert.check_count }
        field(:alert_number, descriptions.fetch(:alert_number), type: :integer) { alert.next_alert_id }
        field(:affected_user_id, descriptions.fetch(:affected_user_id), type: :integer) { alert.user_id }
        field(:affected_user_login, descriptions.fetch(:affected_user_login), type: :string) { alert.user&.login }

        if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :vps)
          field(:vps_id, descriptions.fetch(:vps_id), type: :integer) do
            VpsAdmin::API::Plugins::Monitoring::Events.related_vps(alert.object)&.id
          end
          field(:vps_hostname, descriptions.fetch(:vps_hostname), type: :string) do
            VpsAdmin::API::Plugins::Monitoring::Events.related_vps(alert.object)&.hostname
          end
        end

        if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :dataset)
          field(:dataset_id, descriptions.fetch(:dataset_id), type: :integer) do
            alert.object.id if defined?(::Dataset) && alert.object.is_a?(::Dataset)
          end
          field(:dataset_full_name, descriptions.fetch(:dataset_full_name), type: :string) do
            alert.object.full_name if defined?(::Dataset) && alert.object.is_a?(::Dataset)
          end
        end

        if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :dns)
          field(:dns_zone_id, descriptions.fetch(:dns_zone_id), type: :integer) do
            VpsAdmin::API::Plugins::Monitoring::Events.dns_zone(alert.object)&.id
          end
          field(:dns_zone_name, descriptions.fetch(:dns_zone_name), type: :string) do
            VpsAdmin::API::Plugins::Monitoring::Events.dns_zone(alert.object)&.name
          end
          field(:dns_server_id, descriptions.fetch(:dns_server_id), type: :integer) do
            VpsAdmin::API::Plugins::Monitoring::Events.dns_server(alert.object)&.id
          end
          field(:dns_server_name, descriptions.fetch(:dns_server_name), type: :string) do
            VpsAdmin::API::Plugins::Monitoring::Events.dns_server(alert.object)&.name
          end
          field(:transfer_status, descriptions.fetch(:transfer_status), type: :string) do
            VpsAdmin::API::Plugins::Monitoring::Events.transfer_value(
              alert.object,
              :last_transfer_status
            )
          end
          field(:transfer_reason_code, descriptions.fetch(:transfer_reason_code), type: :string) do
            VpsAdmin::API::Plugins::Monitoring::Events.transfer_value(
              alert.object,
              :last_transfer_reason_code
            )
          end
          field(:transfer_reason, descriptions.fetch(:transfer_reason), type: :string) do
            VpsAdmin::API::Plugins::Monitoring::Events.transfer_value(
              alert.object,
              :last_transfer_reason
            )
          end
        end

        if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :pool_role)
          field(:pool_role, descriptions.fetch(:pool_role), type: :string) do
            VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :pool_role)
          end
        end

        if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :threshold)
          field(:threshold, descriptions.fetch(:threshold), type: :number) do
            VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :threshold)
          end
        end

        if VpsAdmin::API::Plugins::Monitoring::Events.field?(profile, :maintenance)
          field(:finish_weekday, descriptions.fetch(:finish_weekday), type: :integer) do
            VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :finish_weekday)
          end
          field(:finish_minutes, descriptions.fetch(:finish_minutes), type: :integer) do
            VpsAdmin::API::Plugins::Monitoring::Events.context_value(context, :finish_minutes)
          end
        end

        field(:created_at, descriptions.fetch(:created_at), type: :datetime) { alert.created_at&.iso8601 }
        field(:updated_at, descriptions.fetch(:updated_at), type: :datetime) { alert.updated_at&.iso8601 }
        field(:last_report_at, descriptions.fetch(:last_report_at), type: :datetime) { alert.last_report_at&.iso8601 }
        field(:saved_until, descriptions.fetch(:saved_until), type: :datetime) { alert.saved_until&.iso8601 }
        field(:duration_seconds, descriptions.fetch(:duration_seconds), type: :integer) do
          VpsAdmin::API::Plugins::Monitoring::Events.duration_seconds(alert)
        end
        extra_payload { extra_payload }

        deliver :email do
          template do
            VpsAdmin::API::Plugins::Monitoring::Events.resolve_template(
              profile,
              alert,
              context
            )
          end
          params do
            VpsAdmin::API::Plugins::Monitoring::Events.template_params(
              profile,
              alert,
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
              affected_user || alert.user,
              context
            )
          end
        end
      end
    end
  end
end
