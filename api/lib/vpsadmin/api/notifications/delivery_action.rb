module VpsAdmin::API::Notifications
  DeliveryResult = Data.define(
    :outcome,
    :provider_message_id,
    :response_status,
    :response_body,
    :response_headers
  ) do
    def initialize(
      outcome: :sent,
      provider_message_id: nil,
      response_status: nil,
      response_body: nil,
      response_headers: nil
    )
      super
    end

    def accepted?
      outcome == :accepted
    end
  end

  class DeliveryPlanningContext
    attr_reader :event, :route_context

    def initialize(event:, route_context:)
      @event = event
      @route_context = route_context
    end

    def build(
      route,
      receiver,
      receiver_action,
      target_value:,
      target_label:,
      template_name: nil,
      target_kind: nil,
      state: 'prepared',
      next_attempt_at: nil,
      payload: nil
    )
      action = receiver_action&.action || 'email'

      VpsAdmin::API::Events::DeliveryPlan.new(
        action:,
        target_kind: target_kind || receiver_action&.target_kind || 'default_recipient',
        target_value:,
        target_label: label(target_label),
        target_secret: receiver_action&.secret,
        template_name: template_name || template_name_for(route, receiver_action),
        event_route: route,
        notification_receiver: receiver,
        notification_target: receiver_action&.notification_target,
        notification_receiver_action: receiver_action,
        state:,
        next_attempt_at:,
        payload:,
        route_context:,
        route_time_interval_state: 'active'
      )
    end

    def direct(action:, target_kind:, target_value:, target_label:, template_name: nil)
      VpsAdmin::API::Events::DeliveryPlan.new(
        action: action.to_s,
        target_kind:,
        target_value:,
        target_label: label(target_label),
        template_name:,
        event_route: nil,
        notification_receiver: nil,
        notification_target: nil,
        notification_receiver_action: nil,
        state: 'prepared',
        route_context: nil,
        route_time_interval_state: 'active'
      )
    end

    def skip(route, receiver, receiver_action, reason, route_time_interval_state: 'active')
      VpsAdmin::API::Events::DeliveryPlan.new(
        action: receiver_action&.action || 'email',
        target_kind: receiver_action&.target_kind || 'default_recipient',
        target_value: receiver_action&.target_value,
        target_label: label(receiver_action&.display_target || receiver&.label),
        template_name: template_name_for(route, receiver_action),
        event_route: route,
        notification_receiver: receiver,
        notification_target: receiver_action&.notification_target,
        notification_receiver_action: receiver_action,
        state: 'skipped',
        error_summary: reason,
        route_context:,
        route_time_interval_state:
      )
    end

    def label(value)
      return if value.nil?

      value.to_s[0, VpsAdmin::API::Events::DELIVERY_LABEL_LIMIT]
    end

    def template_name_for(route, receiver_action)
      unless receiver_action.nil? || DeliveryActions.template_capable?(receiver_action.action)
        return
      end

      route_template_name = route&.template_name.presence
      return route_template_name if route_template_name
      return unless receiver_action && DeliveryActions.template_capable?(receiver_action.action)

      VpsAdmin::API::Events.template_name_for(
        event,
        receiver_action.action,
        route_context:
      )
    end
  end

  module DeliveryActions
    class Base
      TEST_EVENT_SOURCE_CLASS = 'VpsAdmin::API::Resources::Event::Test'.freeze
      GROUP_CAPABLE_TEMPLATES = %w[vps_oom_report].freeze

      class << self
        attr_reader :action_name, :action_label, :target_kinds, :queue, :routing_key,
                    :config_section, :default_concurrency, :default_rate_limits,
                    :template_context_fallbacks, :template_capable

        def action(name, label:, queue:, routing_key:, default_concurrency:,
                   default_rate_limits:, config_section: name,
                   template_context_fallbacks: [], templates: false)
          @action_name = name.to_s.freeze
          @action_label = label.to_s.freeze
          @queue = queue.to_s.freeze
          @routing_key = routing_key.to_s.freeze
          @config_section = config_section.to_s.freeze
          @default_concurrency = Integer(default_concurrency)
          @default_rate_limits = default_rate_limits
                                 .to_h
                                 .transform_keys(&:to_s)
                                 .transform_values { |value| Integer(value) }
                                 .freeze
          @template_context_fallbacks = Array(template_context_fallbacks)
                                        .map(&:to_sym)
                                        .freeze
          @template_capable = templates == true
          @target_kinds = {}.freeze
        end

        def target_kind(name, label:)
          @target_kinds = target_kinds.merge(name.to_s => label.to_s).freeze
        end
      end

      def initialize(
        config: nil,
        monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        sleeper: ->(seconds) { sleep(seconds) }
      )
        @config = config
        @monotonic_clock = monotonic_clock
        @sleeper = sleeper
      end

      def config
        @config || Config.load
      end

      def name
        self.class.action_name
      end

      def label
        self.class.action_label
      end

      def target_kinds
        self.class.target_kinds
      end

      def queue_name
        self.class.queue
      end

      def routing_key
        self.class.routing_key
      end

      def config_section
        self.class.config_section
      end

      def default_concurrency
        self.class.default_concurrency
      end

      def template_context_actions
        [name.to_sym, *self.class.template_context_fallbacks]
      end

      def available?
        true
      end

      def validate_target(_target); end

      def normalize_target_value(_target_kind, value)
        value
      end

      def identity_key(target_kind:, target_value:, secret: nil)
        value = normalize_target_value(target_kind, target_value)
        value.present? ? "#{target_kind}:#{value}" : nil
      end

      def display_target(target)
        target.target_value.presence || target.target_kind.tr('_', ' ')
      end

      def receiver_action_available?(target)
        return false unless available?
        return false unless target && target.action == name
        return false unless target.target_enabled
        return false unless target.delivery_method_enabled?

        target_available?(target)
      end

      def target_available?(_target)
        true
      end

      def default_target_kind
        'custom'
      end

      def verification_required?(_target)
        false
      end

      def admin_verification_skippable?(_target)
        false
      end

      def plan_delivery(context:, route:, receiver:, receiver_action:)
        context.build(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.display_target
        )
      end

      def direct_delivery_plans(context:)
        []
      end

      def prepare_delivery(_delivery); end

      def prepared?(delivery)
        delivery.payload.present?
      end

      def deliver(_delivery)
        raise NotImplementedError, "#{self.class} must implement #deliver"
      end

      def select_due_deliveries(limit:, scan_limit:, due_scope:)
        due_scope.call.limit(limit).to_a
      end

      def throttle_delay(_delivery, _worker_state)
        nil
      end

      def exception_response_status(error)
        smtp_response_status(exception_response(error))
      end

      def exception_response_body(error)
        smtp_response_body(exception_response(error))
      end

      protected

      def action_config
        config.fetch(config_section, {})
      end

      def truncate_body(body)
        return if body.nil?

        body.to_s.byteslice(0, RESPONSE_BODY_LIMIT)
      end

      def response_headers(response)
        return {} unless response.respond_to?(:to_hash)

        headers = {}
        truncated = false

        response.to_hash.each do |name, values|
          raw_key = name.to_s.downcase
          key = truncate_header_part(raw_key, RESPONSE_HEADER_NAME_LIMIT)
          raw_values = Array(values)
          truncated ||= key.bytesize < raw_key.bytesize
          truncated ||= raw_values.length > RESPONSE_HEADER_VALUE_COUNT_LIMIT
          vals = raw_values.first(RESPONSE_HEADER_VALUE_COUNT_LIMIT).map do |value|
            raw_value = value.to_s
            ret = truncate_header_part(raw_value, RESPONSE_HEADER_VALUE_LIMIT)
            truncated ||= ret.bytesize < raw_value.bytesize
            ret
          end
          candidate = headers.merge(key => vals)

          if JSON.dump(candidate).bytesize > RESPONSE_HEADERS_LIMIT
            truncated = true
            break
          end

          headers = candidate
        end

        truncated ? mark_headers_truncated(headers) : headers
      end

      def truncate_header_part(value, limit)
        value.byteslice(0, limit).to_s.scrub
      end

      def mark_headers_truncated(headers)
        ret = headers.dup

        loop do
          candidate = ret.merge(RESPONSE_HEADERS_TRUNCATED)
          return candidate if JSON.dump(candidate).bytesize <= RESPONSE_HEADERS_LIMIT || ret.empty?

          ret.delete(ret.keys.last)
        end
      end

      def smtp_response_status(response)
        return unless response.respond_to?(:status)

        status = response.status
        status.to_i if status.present?
      end

      def smtp_response_body(response)
        return if response.nil?

        body = response.respond_to?(:string) ? response.string : response.to_s
        truncate_body(body)
      end

      def exception_response(error)
        error.response if error.respond_to?(:response)
      end

      def monotonic_time
        @monotonic_clock.call
      end

      def truthy_config?(value)
        value == true || value.to_s.casecmp('true') == 0 || value.to_s == '1'
      end

      def template_name_for_delivery(delivery, action = name)
        event = delivery.event
        return if event.source_class == TEST_EVENT_SOURCE_CLASS

        delivery.template_name.presence&.to_sym ||
          VpsAdmin::API::Events.template_name_for(event, action, delivery:)
      end

      def generic_group_rendering?(delivery)
        return false unless delivery.event_delivery_group_id

        event_types = delivery.group_events.distinct.limit(2).pluck(:event_type)
        template_name = template_name_for_delivery(delivery)

        event_types.length != 1 ||
          !GROUP_CAPABLE_TEMPLATES.include?(template_name.to_s)
      end

      def grouped_template_available?(delivery, action = name)
        user = delivery.recipient_user || delivery.event.user
        VpsAdmin::API::Events.template_available?(
          :event_group,
          nil,
          user&.language,
          protocol: action
        )
      end

      def grouped_template_options_for(delivery, event_limit:, email: false)
        events = delivery.group_events.limit(event_limit).to_a
        event_count = delivery.event_count
        user = delivery.recipient_user || delivery.event.user
        opts = {
          user:,
          vars: {
            base_url: VpsAdmin::API::Events.webui_url,
            user:,
            group_events: events,
            group_event_count: event_count,
            group_truncated_count: [event_count - events.length, 0].max,
            group_labels: delivery.group_labels || {}
          }
        }

        if email
          opts.merge!(
            to: VpsAdmin::API::Events.email_target_addresses(delivery.event, delivery),
            include_default_recipients: false,
            include_template_recipients: false
          )
        end

        opts
      end
    end

    @classes = {}
    @instances = {}

    module_function

    def register(action_class)
      validate_class!(action_class)
      name = action_class.action_name
      raise ArgumentError, "notification action #{name.inspect} is already registered" if @classes.has_key?(name)

      duplicate_queue = @classes.values.find { |klass| klass.queue == action_class.queue }
      if duplicate_queue
        raise ArgumentError, "notification queue #{action_class.queue.inspect} is already registered"
      end

      duplicate_key = @classes.values.find { |klass| klass.routing_key == action_class.routing_key }
      if duplicate_key
        raise ArgumentError, "notification routing key #{action_class.routing_key.inspect} is already registered"
      end

      @classes[name] = action_class
      action_class
    end

    def fetch(name)
      key = name.to_s
      @instances[key] ||= @classes.fetch(key).new
    end

    def build(name, **)
      @classes.fetch(name.to_s).new(**)
    end

    def known?(name)
      @classes.has_key?(name.to_s)
    end

    def names
      @classes.keys
    end

    def labels
      @classes.transform_values(&:action_label)
    end

    def available?(name)
      fetch(name).available?
    rescue KeyError
      false
    end

    def available_names
      @classes.keys.select { |name| fetch(name).available? }
    end

    def available_labels
      labels.slice(*available_names)
    end

    def target_kind_labels
      @classes.values.each_with_object({}) do |klass, ret|
        klass.target_kinds.each do |name, label|
          previous = ret[name]
          if previous && previous != label
            raise ArgumentError, "conflicting label for notification target kind #{name.inspect}"
          end

          ret[name] = label
        end
      end
    end

    def direct_delivery_plans(context:)
      available_names.flat_map do |name|
        fetch(name).direct_delivery_plans(context:)
      end
    end

    def queue_name(name)
      @classes.fetch(name.to_s).queue
    end

    def routing_key(name)
      @classes.fetch(name.to_s).routing_key
    end

    def default_rate_limits
      @classes.transform_values(&:default_rate_limits)
    end

    def template_capable?(name)
      @classes.fetch(name.to_s).template_capable
    rescue KeyError
      false
    end

    def validate_class!(action_class)
      unless action_class < Base && action_class.action_name.present? && action_class.action_label.present? &&
             action_class.queue.present? && action_class.routing_key.present? &&
             action_class.config_section.present? && action_class.default_concurrency.to_i > 0 &&
             action_class.default_rate_limits&.keys&.sort == RateLimits.periods.sort &&
             action_class.default_rate_limits.values.all?(&:positive?) &&
             valid_template_metadata?(action_class) &&
             action_class.target_kinds&.any? &&
             action_class.instance_method(:deliver).owner != Base
        raise ArgumentError, "incomplete notification delivery action #{action_class}"
      end
    end

    def valid_template_metadata?(action_class)
      fallbacks = action_class.template_context_fallbacks
      return false if fallbacks.any? && !action_class.template_capable

      fallbacks.all? do |fallback|
        fallback_class = @classes[fallback.to_s]
        fallback_class && fallback_class.template_capable
      end
    end
    private_class_method :validate_class!, :valid_template_metadata?
  end
end
