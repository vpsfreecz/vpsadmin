module VpsAdmin::API
  module Events
    EVALUATION_TIMEOUT = 0.5

    Type = Struct.new(
      :name,
      :label,
      :category,
      :severity,
      :parameters
    )

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
    )

    @types = {}

    module_function

    def register(name, label:, category:, severity: :info, parameters: {})
      @types[name.to_s] = Type.new(
        name: name.to_s,
        label:,
        category: category.to_s,
        severity: severity.to_s,
        parameters:
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

    def parameter_field?(field)
      return false unless field.to_s.start_with?('parameters.')

      name = field.to_s.delete_prefix('parameters.')
      types.any? { |type| type.parameters.has_key?(name.to_sym) || type.parameters.has_key?(name) }
    end

    def emit!(event_type, user: nil, vps: nil, source: nil, source_class: nil,
              source_id: nil, subject: nil, summary: nil, parameters: {},
              severity: nil, category: nil, ip_addr: nil, route: true)
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
          ensure_default_routes

          result = plan_route

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
            target_label: event.user.email
          )
        end

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.target_value
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
          target_label:,
          template_name: receiver_action.template_name,
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
          target_label: receiver_action&.display_target || receiver&.label,
          template_name: receiver_action&.template_name,
          event_route: route,
          notification_receiver: receiver,
          notification_receiver_action: receiver_action,
          state: 'skipped',
          error_summary: reason
        )
      end

      def routing_state_for(deliveries)
        deliveries.any? { |delivery| delivery.state != 'skipped' } ? 'routed' : 'suppressed'
      end

      def deduplicate(deliveries)
        deliveries.uniq do |delivery|
          [
            delivery.action,
            delivery.target_kind,
            delivery.target_value,
            delivery.notification_receiver&.id,
            delivery.notification_receiver_action&.id,
            delivery.template_name,
            delivery.state,
            delivery.error_summary
          ]
        end
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
      parameters: {
        cgroup: 'Affected cgroup',
        count: 'OOM count',
        killed_name: 'Killed process'
      }
    )

    register(
      'vps.oom_prevention',
      label: 'OOM prevention',
      category: 'vps',
      severity: :critical,
      parameters: {
        action: 'Prevention action',
        reason: 'Reason'
      }
    )
  end
end
