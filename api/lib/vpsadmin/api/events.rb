require 'json'
require 'time'

module VpsAdmin::API
  module Events
    EVALUATION_TIMEOUT = 0.5
    DELIVERY_LABEL_LIMIT = 255

    Type = Struct.new(
      :name,
      :label,
      :category,
      :severity,
      :parameters,
      :email_template
    )

    RequestInfo = Struct.new(:ip)

    DeliveryPlan = Struct.new(
      :action,
      :target_kind,
      :target_value,
      :target_label,
      :template_name,
      :event_route,
      :notification_receiver,
      :notification_receiver_action,
      :state,
      :error_summary,
      :next_attempt_at
    )

    RouteResult = Struct.new(
      :routing_state,
      :matched_event_route,
      :deliveries
    ) do
      def suppressed_by_mute?
        routing_state == 'suppressed' &&
          deliveries.any? do |delivery|
            receiver = delivery.notification_receiver
            receiver&.enabled? && receiver.mute?
          end
      end
    end

    @types = {}

    module_function

    def register(name, label:, category:, severity: :info, parameters: {},
                 email_template: nil)
      @types[name.to_s] = Type.new(
        name: name.to_s,
        label:,
        category: category.to_s,
        severity: severity.to_s,
        parameters:,
        email_template: email_template&.to_s
      )
    end

    def types
      @types.values.sort_by(&:name)
    end

    def type_for(name)
      @types[name.to_s]
    end

    def type_labels
      types.to_h { |type| [type.name, type.label] }
    end

    def field_labels(event_type: nil)
      EventRouteMatcher.field_labels(event_type:)
    end

    def email_template_name_for(event, action = nil)
      (action&.template_name.presence || type_for(event.event_type)&.email_template)&.to_sym
    end

    def email_template_options_for(event, delivery)
      opts = {
        user: event.user,
        vars: email_vars_for(event)
      }

      if delivery.custom_target_kind?
        opts[:to] = email_target_addresses(event, delivery)
        opts[:include_default_recipients] = false
        opts[:include_template_recipients] = false
      end

      opts
    end

    def email_custom_options_for(event, delivery)
      {
        user: event.user,
        from: MailTemplates.default_from,
        to: email_target_addresses(event, delivery),
        subject: event.subject,
        text_plain: custom_email_body(event)
      }
    end

    def email_target_addresses(event, delivery)
      if delivery.default_recipient_target_kind?
        address = delivery.target_value.presence
        address = nil if address == 'default'
        address ||= event.user&.email
        raise ArgumentError, 'event has no user e-mail recipient' if address.blank?

        return [address]
      end

      addresses = delivery.target_value.to_s.split(',').map(&:strip).reject(&:blank?)
      raise ArgumentError, 'e-mail delivery has no recipient address' if addresses.empty?

      addresses
    end

    def email_vars_for(event)
      return event.runtime_email_vars if event.runtime_email_vars

      case event.event_type
      when 'user.created'
        user_email_vars(event)
      when 'user.suspended', 'user.soft_deleted', 'user.resumed', 'user.revived'
        user_state_email_vars(event)
      when 'user.new_login'
        user_new_login_email_vars(event)
      when 'user.new_token'
        user_new_token_email_vars(event)
      when 'user.totp_recovery_code_used'
        user_totp_recovery_email_vars(event)
      when 'user.failed_logins'
        user_failed_logins_email_vars(event)
      when 'vps.incident_report'
        incident_email_vars(event)
      when 'vps.oom_report'
        oom_report_email_vars(event)
      when 'vps.oom_prevention'
        oom_prevention_email_vars(event)
      else
        {
          event:,
          user: event.user,
          parameters: event.parameters || {}
        }
      end
    end

    def user_email_vars(event)
      {
        user: event.user || user_source(event)
      }
    end

    def user_state_email_vars(event)
      {
        user: event.user,
        state: object_state_source(event) || object_state_from_parameters(event)
      }
    end

    def user_new_login_email_vars(event)
      session = user_session_source(event)
      authorization = find_from_parameters(event, ::Oauth2Authorization, 'authorization_id')
      user_device = authorization&.user_device ||
                    find_from_parameters(event, ::UserDevice, 'user_device_id')

      {
        user: event.user || session&.user,
        user_session: session,
        authorization:,
        user_device:
      }
    end

    def user_new_token_email_vars(event)
      session = user_session_source(event)

      {
        user: event.user || session&.user,
        user_session: session
      }
    end

    def user_totp_recovery_email_vars(event)
      params = event.parameters || {}
      request_ip = params['request_ip'] || params[:request_ip]
      totp_device = user_totp_device_source(event) ||
                    find_from_parameters(event, ::UserTotpDevice, 'totp_device_id')

      {
        user: event.user,
        totp_device:,
        request: request_ip.present? ? RequestInfo.new(request_ip) : nil,
        time: parse_time(params['used_at'] || params[:used_at]) || event.created_at
      }
    end

    def user_failed_logins_email_vars(event)
      {
        user: event.user,
        attempt_groups: failed_login_groups(event)
      }
    end

    def user_source(event)
      source = event.source
      return unless source.is_a?(::User)
      return if event.user_id.present? && source.id != event.user_id

      source
    end

    def object_state_source(event)
      event.source if event.source.is_a?(::ObjectState)
    end

    def object_state_from_parameters(event)
      params = event.parameters || {}

      ::ObjectState.new(
        state: params['state'] || params[:state],
        reason: params['reason'] || params[:reason],
        expiration_date: parse_time(params['expiration_date'] || params[:expiration_date])
      )
    end

    def user_session_source(event)
      user_owned_source(event, ::UserSession)
    end

    def user_totp_device_source(event)
      user_owned_source(event, ::UserTotpDevice)
    end

    def find_from_parameters(event, model, key)
      value = (event.parameters || {})[key] || (event.parameters || {})[key.to_sym]
      return if value.blank?

      scope = model.all
      if event.user_id.present? && model.column_names.include?('user_id')
        scope = scope.where(user_id: event.user_id)
      end

      scope.find_by(id: value)
    end

    def failed_login_groups(event)
      params = event.parameters || {}
      group_ids = Array(params['attempt_group_ids'] || params[:attempt_group_ids])
      ids = group_ids.flatten.map(&:to_i).uniq
      return [] if ids.empty?

      attempts = ::UserFailedLogin
                 .includes(:user_agent)
                 .where(user_id: event.user_id)
                 .where(id: ids)
                 .to_a
                 .index_by(&:id)

      group_ids.map do |group|
        Array(group).filter_map { |id| attempts[id.to_i] }
      end
    end

    def user_owned_source(event, model)
      source = event.source
      return unless source.is_a?(model)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def incident_email_vars(event)
      incident = event.source if event.source.is_a?(::IncidentReport)
      raise ArgumentError, 'incident report source is missing' unless incident

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        user: incident.user,
        vps: incident.vps,
        incident:
      }
    end

    def oom_report_email_vars(event)
      params = event.parameters || {}
      selected_reports = oom_reports_from_ids(
        event,
        params['selected_report_ids'] || params[:selected_report_ids]
      )
      reports = oom_reports_from_batch(event, selected_reports)

      raise ArgumentError, 'OOM report parameters are missing report ids' if reports.empty?

      selected_reports = reports.first(30) if selected_reports.empty?

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        vps: event.vps || reports.first.vps,
        all_oom_reports: reports,
        all_oom_count: params['oom_count'] || params[:oom_count] || reports.sum(&:count),
        selected_oom_reports: selected_reports,
        selected_oom_count: params['selected_oom_count'] || params[:selected_oom_count] || selected_reports.sum(&:count)
      }
    end

    def oom_prevention_email_vars(event)
      params = event.parameters || {}
      vps = event.vps

      raise ArgumentError, 'OOM prevention VPS is missing' unless vps

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        vps:,
        action: (params['action'] || params[:action])&.to_sym,
        ooms_in_period: params['ooms_in_period'] || params[:ooms_in_period],
        period_seconds: params['period_seconds'] || params[:period_seconds]
      }
    end

    def oom_reports_from_ids(event, ids)
      ids = Array(ids).map(&:to_i).uniq
      return [] if ids.empty?

      reports = oom_report_scope(event).where(id: ids).to_a.index_by(&:id)
      ids.filter_map { |id| reports[id] }
    end

    def oom_reports_from_batch(event, selected_reports)
      params = event.parameters || {}
      batch_time = parse_batch_time(params['batch_reported_at'] || params[:batch_reported_at])

      return selected_reports if batch_time.nil?

      scope = oom_report_scope(event).order('oom_reports.created_at')
      last_reported_id = params['last_reported_id'] || params[:last_reported_id]
      scope = scope.where('oom_reports.id > ?', last_reported_id.to_i) if last_reported_id.present?
      scope = scope.where('oom_reports.created_at <= ?', batch_time)
      scope.to_a
    end

    def oom_report_scope(event)
      raise ArgumentError, 'OOM report event has no user' if event.user_id.blank?

      scope = ::OomReport.joins(:vps).where(vpses: { user_id: event.user_id })
      scope = scope.where(vps_id: event.vps_id) if event.vps_id.present?
      scope.where(ignored: false)
    end

    def parse_batch_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def parse_time(value)
      parse_batch_time(value)
    end

    def custom_email_body(event)
      ret = [
        event.summary.presence,
        "Event type: #{event.event_type}",
        "Severity: #{event.severity}",
        event.vps && "VPS: ##{event.vps.id} #{event.vps.hostname}",
        event.ip_addr && "IP address: #{event.ip_addr}",
        "Parameters:\n#{JSON.pretty_generate(event.parameters || {})}"
      ].compact

      ret.join("\n\n")
    end

    def parameter_field?(field)
      return false unless field.to_s.start_with?('parameters.')

      name = field.to_s.delete_prefix('parameters.')
      types.any? { |type| type.parameters.has_key?(name.to_sym) || type.parameters.has_key?(name) }
    end

    def plan(event_type, user: nil, vps: nil, subject: nil, summary: nil,
             parameters: {}, severity: nil, category: nil, ip_addr: nil)
      type = type_for(event_type)
      if user && vps && vps.user_id != user.id
        raise ArgumentError, 'user and VPS owner do not match'
      end

      owner = user || vps&.user
      event = ::Event.new(
        user: owner,
        vps:,
        event_type: event_type.to_s,
        category: category || type&.category || 'general',
        severity: severity || type&.severity || 'info',
        subject: subject || type&.label || event_type.to_s,
        summary:,
        parameters: parameters || {},
        ip_addr:
      )

      Router.new(event).plan
    end

    def emit!(event_type, user: nil, vps: nil, source: nil, source_class: nil,
              source_id: nil, subject: nil, summary: nil, parameters: {},
              severity: nil, category: nil, ip_addr: nil, route: true,
              email_vars: nil)
      type = type_for(event_type)
      if user && vps && vps.user_id != user.id
        raise ArgumentError, 'user and VPS owner do not match'
      end

      owner = user || vps&.user

      event = ::Event.create!(
        user: owner,
        vps:,
        event_type: event_type.to_s,
        category: category || type&.category,
        severity: severity || type&.severity,
        subject: subject || type&.label,
        summary:,
        parameters: parameters || {},
        source_class: source_class || source&.class&.name,
        source_id: source_id || source&.id,
        ip_addr:
      )
      event.runtime_email_vars = email_vars if email_vars

      route!(event) if route

      event
    end

    def route!(event)
      Router.new(event).route!
    end

    class Router
      attr_reader :event

      def initialize(event)
        @event = event
      end

      def route!
        event.class.transaction do
          event.lock!
          event.event_deliveries.delete_all
          result = plan

          event.update!(
            routing_state: result.routing_state,
            matched_event_route: result.matched_event_route
          )

          result.deliveries.each do |delivery|
            create_delivery!(delivery)
          end
        end

        event
      end

      def plan
        ensure_default_routes
        plan_route
      end

      protected

      def ensure_default_routes
        return unless event.user

        ::NotificationReceiver.ensure_defaults_for!(event.user)
      end

      def plan_route
        deadline = monotonic_time + EVALUATION_TIMEOUT
        deliveries = []
        first_matched_route = nil

        child_routes(nil).each do |route|
          break if deadline_expired?(deadline)
          next unless route.matches?(event, deadline:)

          first_matched_route ||= route
          deliveries.concat(process_route(route, deadline))

          break unless route.continue?
        end

        if deliveries.empty?
          deliveries = [skipped_delivery(nil, nil, nil, 'no route matched the event')]
        end

        first_delivery_route = deliveries.map(&:event_route).compact.first

        RouteResult.new(
          routing_state: routing_state_for(deliveries),
          matched_event_route: first_delivery_route || first_matched_route,
          deliveries: deduplicate(deliveries)
        )
      end

      def process_route(route, deadline)
        ::EventRoute.increment_counter(:hit_count, route.id)

        deliveries = []
        matched_child = false

        child_routes(route.id).each do |child|
          break if deadline_expired?(deadline)
          next unless child.matches?(event, deadline:)

          matched_child = true
          deliveries.concat(process_route(child, deadline))

          break unless child.continue?
        end

        return deliveries if matched_child

        deliveries_for_route(route)
      end

      def child_routes(parent_id)
        routes_by_parent[parent_id] || []
      end

      def routes_by_parent
        @routes_by_parent ||= if event.user
                                event.user.event_routes
                                     .where(enabled: true)
                                     .includes(:event_route_matchers, notification_receiver: :notification_receiver_actions)
                                     .order(:position, :id)
                                     .to_a
                                     .group_by(&:parent_id)
                              else
                                {}
                              end
      end

      def deliveries_for_route(route)
        receiver = route.notification_receiver

        return [skipped_delivery(route, nil, nil, 'route has no receiver')] unless receiver

        unless receiver.enabled?
          return [skipped_delivery(route, receiver, nil, 'receiver is disabled')]
        end

        if receiver.mute?
          return [skipped_delivery(route, receiver, nil, 'receiver does not notify')]
        end

        actions = receiver.notification_receiver_actions.select(&:enabled?)

        if actions.empty?
          return [skipped_delivery(route, receiver, nil, 'receiver has no enabled actions')]
        end

        actions.map { |receiver_action| delivery_from_receiver_action(route, receiver, receiver_action) }
      end

      def delivery_from_receiver_action(route, receiver, receiver_action)
        unless receiver_action.deliverable?
          reason = receiver_action.enabled? ? 'receiver action is not verified' : 'receiver action is disabled'
          return skipped_delivery(route, receiver, receiver_action, reason)
        end

        case receiver_action.action
        when 'email'
          email_delivery(route, receiver, receiver_action)
        when 'telegram'
          telegram_delivery(route, receiver, receiver_action)
        when 'webhook'
          webhook_delivery(route, receiver, receiver_action)
        else
          skipped_delivery(route, receiver, receiver_action, 'unknown receiver action')
        end
      end

      def email_delivery(route, receiver, receiver_action)
        if receiver_action.default_recipient_target_kind?
          if event.user.nil?
            return skipped_delivery(route, receiver, receiver_action, 'event has no user')
          end

          return build_delivery(
            route,
            receiver,
            receiver_action,
            target_value: 'default',
            target_label: 'Default recipient'
          )
        end

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: delivery_label(receiver_action.target_value)
        )
      end

      def telegram_delivery(route, receiver, receiver_action)
        return skipped_delivery(route, receiver, receiver_action, 'Telegram chat is not linked') if receiver_action.target_value.blank?

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.display_target
        )
      end

      def webhook_delivery(route, receiver, receiver_action)
        return skipped_delivery(route, receiver, receiver_action, 'webhook URL is not configured') if receiver_action.target_value.blank?

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.label,
          state: 'queued',
          next_attempt_at: Time.now
        )
      end

      def build_delivery(route, receiver, receiver_action, target_value:, target_label:, state: 'planned', next_attempt_at: nil)
        DeliveryPlan.new(
          action: receiver_action.action,
          target_kind: receiver_action.target_kind,
          target_value:,
          target_label: delivery_label(target_label),
          template_name: delivery_template_name(receiver_action),
          event_route: route,
          notification_receiver: receiver,
          notification_receiver_action: receiver_action,
          state:,
          next_attempt_at:
        )
      end

      def skipped_delivery(route, receiver, receiver_action, reason)
        DeliveryPlan.new(
          action: receiver_action&.action || 'email',
          target_kind: receiver_action&.target_kind || 'default_recipient',
          target_value: receiver_action&.target_value,
          target_label: delivery_label(receiver_action&.display_target || receiver&.label),
          template_name: receiver_action&.template_name,
          event_route: route,
          notification_receiver: receiver,
          notification_receiver_action: receiver_action,
          state: 'skipped',
          error_summary: reason
        )
      end

      def delivery_label(label)
        return if label.nil?

        label.to_s[0, DELIVERY_LABEL_LIMIT]
      end

      def delivery_template_name(receiver_action)
        return receiver_action.template_name if receiver_action.template_name.present?
        return unless receiver_action.email_action?

        VpsAdmin::API::Events.email_template_name_for(event, receiver_action)
      end

      def routing_state_for(deliveries)
        deliveries.any? { |delivery| delivery.state != 'skipped' } ? 'routed' : 'suppressed'
      end

      def deduplicate(deliveries)
        deliveries.uniq do |delivery|
          deduplication_key(delivery)
        end
      end

      def deduplication_key(delivery)
        if delivery.state == 'skipped'
          return [
            delivery.state,
            delivery.event_route&.id,
            delivery.notification_receiver&.id,
            delivery.notification_receiver_action&.id,
            delivery.error_summary
          ]
        end

        [
          delivery.action,
          delivery.target_kind,
          delivery.target_value,
          delivery.template_name,
          delivery.state
        ]
      end

      def create_delivery!(delivery)
        event.event_deliveries.create!(
          event_route: delivery.event_route,
          notification_receiver: delivery.notification_receiver,
          notification_receiver_action: delivery.notification_receiver_action,
          action: delivery.action,
          target_kind: delivery.target_kind,
          target_value: delivery.target_value,
          target_label: delivery.target_label,
          template_name: delivery.template_name,
          state: delivery.state,
          error_summary: delivery.error_summary,
          next_attempt_at: delivery.next_attempt_at
        )
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def deadline_expired?(deadline)
        monotonic_time >= deadline
      end
    end

    register(
      'user.created',
      label: 'User account created',
      category: 'account',
      severity: :info,
      email_template: :user_create,
      parameters: {
        login: 'User login',
        email: 'User e-mail',
        level: 'User level',
        object_state: 'Initial account state',
        create_vps: 'Whether an initial VPS was requested',
        active: 'Whether the account was activated'
      }
    )

    register(
      'user.suspended',
      label: 'User account suspended',
      category: 'account',
      severity: :warning,
      email_template: :user_suspend,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.soft_deleted',
      label: 'User account disabled',
      category: 'account',
      severity: :warning,
      email_template: :user_soft_delete,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.resumed',
      label: 'User account resumed',
      category: 'account',
      severity: :info,
      email_template: :user_resume,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.revived',
      label: 'User account restored',
      category: 'account',
      severity: :info,
      email_template: :user_revive,
      parameters: {
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date'
      }
    )

    register(
      'user.new_login',
      label: 'New sign-in',
      category: 'security',
      severity: :warning,
      email_template: :user_new_login,
      parameters: {
        auth_type: 'Authentication type',
        client_ip_addr: 'Client IP address',
        api_ip_addr: 'API IP address',
        client_version: 'Client version',
        user_agent: 'User agent',
        user_device_id: 'User device ID',
        authorization_id: 'OAuth authorization ID',
        oauth2_client_id: 'OAuth client ID'
      }
    )

    register(
      'user.new_token',
      label: 'New access token',
      category: 'security',
      severity: :warning,
      email_template: :user_new_token,
      parameters: {
        auth_type: 'Authentication type',
        client_ip_addr: 'Client IP address',
        api_ip_addr: 'API IP address',
        client_version: 'Client version',
        scope: 'Token scope',
        token_lifetime: 'Token lifetime',
        label: 'Token label'
      }
    )

    register(
      'user.totp_recovery_code_used',
      label: 'TOTP recovery code used',
      category: 'security',
      severity: :critical,
      email_template: :user_totp_recovery_code_used,
      parameters: {
        totp_device_id: 'TOTP device ID',
        totp_device_label: 'TOTP device label',
        request_ip: 'Request IP address',
        used_at: 'Recovery time'
      }
    )

    register(
      'user.failed_logins',
      label: 'Failed sign-in report',
      category: 'security',
      severity: :warning,
      email_template: :user_failed_logins,
      parameters: {
        attempt_count: 'Failed attempt count',
        group_count: 'Attempt group count',
        attempt_group_ids: 'Failed attempt IDs grouped by similarity',
        ip_addrs: 'Client IP addresses',
        auth_types: 'Authentication types',
        reasons: 'Failure reasons'
      }
    )

    register(
      'user.test_notification',
      label: 'Test notification',
      category: 'test',
      severity: :info,
      parameters: {
        note: 'Test note'
      }
    )

    register(
      'vps.incident_report',
      label: 'Incident report',
      category: 'incidents',
      severity: :warning,
      email_template: :vps_incident_report,
      parameters: {
        subject: 'Report subject',
        text: 'Report text',
        codename: 'Report codename',
        ip_addr: 'Affected IP address',
        vps_id: 'Affected VPS ID'
      }
    )

    register(
      'vps.oom_report',
      label: 'OOM report',
      category: 'vps',
      severity: :warning,
      email_template: :vps_oom_report,
      parameters: {
        stage: 'OOM event stage',
        cgroup: 'Affected cgroup',
        cgroups: 'Affected cgroups',
        count: 'OOM count',
        killed_name: 'Killed process',
        report_count: 'Report count',
        selected_report_count: 'Selected report count',
        selected_oom_count: 'Selected OOM count'
      }
    )

    register(
      'vps.oom_prevention',
      label: 'OOM prevention',
      category: 'vps',
      severity: :critical,
      email_template: :vps_oom_prevention,
      parameters: {
        action: 'Prevention action',
        reason: 'Reason',
        ooms_in_period: 'OOM count in period',
        period_seconds: 'Period in seconds'
      }
    )
  end
end
