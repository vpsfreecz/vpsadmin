require 'json'
require 'time'

module VpsAdmin::API
  module Events
    EVALUATION_TIMEOUT = 0.5
    DELIVERY_LABEL_LIMIT = 255
    PARAMETER_SAMPLE_LIMIT = 30
    FALLBACK_COLLECTION_LIMIT = 100
    TRANSACTION_CHAIN_TERMINAL_STATES = %w[done failed fatal resolved].freeze
    TRANSACTION_CHAIN_FAILED_STATES = %w[failed fatal].freeze
    TRANSACTION_CHAIN_STATE_SEVERITIES = {
      'queued' => 'info',
      'done' => 'info',
      'resolved' => 'info',
      'rollbacking' => 'warning',
      'failed' => 'error',
      'fatal' => 'critical'
    }.freeze
    FIELD_TYPE_OPERATORS = {
      'string' => %w[== != =~ !~ =* !*],
      'integer' => %w[== != > >= < <=],
      'number' => %w[== != > >= < <=],
      'boolean' => %w[== !=],
      'datetime' => %w[== != > >= < <=],
      'string_list' => %w[contains not_contains],
      'integer_list' => %w[contains not_contains]
    }.freeze

    Type = Struct.new(
      :name,
      :label,
      :category,
      :severity,
      :roles,
      :fields,
      :template,
      :default_routed,
      :severity_description,
      :definition
    )

    FieldDefinition = Struct.new(
      :name,
      :description,
      :type,
      :example,
      :choices,
      :block
    ) do
      def initialize(**kwargs)
        super
        self.name = name.to_sym
        self.type = normalize_type(type)
        self.example = default_example if example.nil?
      end

      def operators
        FIELD_TYPE_OPERATORS.fetch(type)
      end

      def to_h
        {
          name: name.to_s,
          description:,
          type:,
          example:,
          operators:
        }.tap do |ret|
          ret[:choices] = choices if choices
        end
      end

      def evaluate(context)
        context.instance_exec(&block) if block
      end

      protected

      def normalize_type(value)
        raise ArgumentError, "event field #{name} must declare a type" if value.nil?

        normalized = value.to_s
        unless FIELD_TYPE_OPERATORS.has_key?(normalized)
          raise ArgumentError, "unsupported event field type #{value.inspect}"
        end

        normalized
      end

      def default_example
        name_s = name.to_s
        return true if type == 'boolean'
        return 123 if type == 'integer' || name_s.end_with?('_id')
        return 3.14 if type == 'number'
        return '2026-07-01T12:00:00Z' if type == 'datetime'
        return [123] if type == 'integer_list'
        return ['example'] if type == 'string_list'
        return 'vps1.example.org' if name_s.include?('hostname')
        return '198.51.100.10' if name_s.include?('ip_addr') || name_s.end_with?('_addr')
        return 'warning' if name_s == 'severity'
        return 'active' if name_s == 'state'

        'example'
      end
    end

    Argument = Struct.new(:name, :type, :optional, :default, :has_default) do
      def validate!(event_name, value, provided:)
        if !provided && !has_default && !optional
          raise ArgumentError, "#{event_name} argument #{name} is required"
        end
        return if value.nil? && optional
        return if type.nil?
        return if valid_type?(value)

        expected = type.is_a?(Array) ? type.join(' or ') : type.to_s
        actual = value.nil? ? 'nil' : value.class.to_s
        raise ArgumentError, "#{event_name} argument #{name} must be #{expected}, got #{actual}"
      end

      def valid_type?(value)
        if type.is_a?(Array)
          type.any? { |candidate| value.is_a?(resolve_type(candidate)) }
        else
          value.is_a?(resolve_type(type))
        end
      end

      def resolve_type(value)
        return value unless value.is_a?(String) || value.is_a?(Symbol)

        value.to_s.safe_constantize || Object.const_get(value.to_s)
      end
    end

    class DeliveryDefinition
      attr_reader :action

      def initialize(action)
        @action = action.to_s
      end

      def template(value = nil, &block)
        @template = block || value
      end

      def params(value = nil, &block)
        @params = block || value
      end

      def vars(value = nil, &block)
        @vars = block || value
      end

      def options(value = nil, &block)
        @options = block || value
      end

      def default_target(value = nil, &block)
        @default_target = block || value
      end

      def custom_target(value = nil, &block)
        @custom_target = block || value
      end

      def system_template(value = true, &block)
        @system_template = block || value
      end

      def custom_body(value = nil, &block)
        @custom_body = block || value
      end

      def custom_options(value = nil, &block)
        @custom_options = block || value
      end

      def static_template_name
        @template.to_s if @template && !@template.respond_to?(:call)
      end

      def evaluate_template(context)
        evaluate(context, @template)
      end

      def evaluate_params(context)
        evaluate(context, @params)
      end

      def evaluate_vars(context)
        evaluate(context, @vars)
      end

      def evaluate_options(context)
        evaluate(context, @options) || {}
      end

      def evaluate_default_target(context)
        evaluate(context, @default_target)
      end

      def evaluate_custom_target(context)
        evaluate(context, @custom_target)
      end

      def evaluate_system_template(context)
        evaluate(context, @system_template) == true
      end

      def evaluate_custom_body(context)
        evaluate(context, @custom_body)
      end

      def evaluate_custom_options(context)
        evaluate(context, @custom_options) || {}
      end

      protected

      def evaluate(context, value)
        value.respond_to?(:call) ? context.instance_exec(&value) : value
      end
    end

    class EventDefinition
      attr_reader :name, :owner, :label, :category_name, :default_severity,
                  :default_routed, :roles, :severity_description,
                  :arguments

      def initialize(name, label:, category:, default_routed:, roles:,
                     owner: nil, severity: :info, template: nil,
                     severity_description: nil)
        @name = name.to_s
        @owner = owner
        @label = label
        @category_name = category.to_s
        @default_severity = severity.to_s
        @default_routed = default_routed ? true : false
        @roles = normalize_roles(roles)
        @severity_description = severity_description
        @fallback_template_name = template&.to_s
        @arguments = {}
        @fields = {}
        @payload_block = nil
        @extra_payload_block = nil
        @delivery_definitions = {}
        @helpers = {}
      end

      def argument(name, type:, optional: false, default: nil)
        @arguments[name.to_sym] = Argument.new(
          name: name.to_sym,
          type:,
          optional:,
          default:,
          has_default: !default.nil?
        )
      end

      %i[user vps source subject summary ip_addr severity category].each do |field|
        define_method(field) do |value = nil, &block|
          instance_variable_set("@#{field}_block", block || proc { value })
        end
      end

      def field(name, description = nil, type: nil, example: nil, choices: nil, &block)
        if description.is_a?(Hash)
          config = description
          description = config[:description] || config[:label]
          type = config.fetch(:type, type)
          example = config.fetch(:example, example)
          choices = config.fetch(:choices, choices)
        end

        @fields[name.to_sym] = FieldDefinition.new(
          name:,
          description: description || name.to_s.tr('_', ' '),
          type:,
          example:,
          choices:,
          block:
        )
      end

      def fields(hash)
        hash.each do |name, config|
          unless config.is_a?(Hash)
            raise ArgumentError, "event field #{name} must declare a type"
          end

          field(name, config)
        end
      end

      def payload(value = nil, &block)
        @payload_block = block || proc { value }
      end

      def extra_payload(&block)
        @extra_payload_block = block
      end

      def deliver(action, &block)
        definition = DeliveryDefinition.new(action)
        definition.instance_exec(&block) if block
        @delivery_definitions[definition.action] = definition
      end

      def delivery(action)
        @delivery_definitions[action.to_s]
      end

      def helper(name, &block)
        @helpers[name.to_sym] = block
      end

      def helper?(name)
        @helpers.has_key?(name.to_sym)
      end

      def call_helper(context, name, *)
        context.instance_exec(*, &@helpers.fetch(name.to_sym))
      end

      def build_context(values = {}, event: nil)
        values = (values || {}).transform_keys(&:to_sym)
        unknown = values.keys - @arguments.keys
        if unknown.any?
          raise ArgumentError, "#{name} does not accept argument #{unknown.first}"
        end

        resolved = {}
        @arguments.each_value do |arg|
          provided = values.has_key?(arg.name)
          value = if provided
                    values.fetch(arg.name)
                  elsif arg.has_default
                    arg.default
                  end
          arg.validate!(name, value, provided:)
          resolved[arg.name] = value if provided || arg.has_default || arg.optional
        end

        EventContext.new(self, resolved, event:)
      end

      def build_context_from_event(event)
        EventContext.new(self, {}, event:)
      end

      def build_attributes(context)
        {
          user: evaluate(context, @user_block),
          vps: evaluate(context, @vps_block),
          source: evaluate(context, @source_block),
          subject: evaluate(context, @subject_block),
          summary: evaluate(context, @summary_block),
          ip_addr: evaluate(context, @ip_addr_block),
          severity: evaluate(context, @severity_block),
          category: evaluate(context, @category_block),
          payload: build_payload(context)
        }.compact
      end

      def template_name
        delivery(:email)&.static_template_name || @fallback_template_name
      end

      def field_metadata
        @fields.values.map(&:to_h)
      end

      def field_for(name)
        @fields[name.to_sym]
      end

      def field_names
        @fields.keys.map(&:to_s)
      end

      def payload_value(event, field)
        case field.to_s
        when 'vps_id'
          event.vps_id || payload_fetch(event.payload, field)
        when 'vps_hostname'
          event.vps&.hostname || payload_fetch(event.payload, field)
        when 'ip_addr'
          event.ip_addr || payload_fetch(event.payload, field)
        else
          payload_fetch(event.payload, field)
        end
      end

      protected

      def payload_fetch(payload, field)
        payload ||= {}
        field_s = field.to_s
        field_sym = field.to_sym
        if payload.has_key?(field_s)
          payload[field_s]
        elsif payload.has_key?(field_sym)
          payload[field_sym]
        end
      end

      def build_payload(context)
        ret =
          if @payload_block
            evaluate(context, @payload_block) || {}
          else
            @fields.each_value.with_object({}) do |field, memo|
              value = field.evaluate(context)
              memo[field.name] = value unless value.nil?
            end
          end
        extra = context.instance_exec(&@extra_payload_block) if @extra_payload_block
        ret.merge!(extra || {})
        ret[:roles] ||= roles
        ret
      end

      def evaluate(context, block)
        context.instance_exec(&block) if block
      end

      def normalize_roles(value)
        ret = Array(value).map(&:to_s).uniq
        raise ArgumentError, "event #{name} must declare at least one role" if ret.empty?

        unsupported = ret - %w[account admin]
        if unsupported.any?
          raise ArgumentError, "event #{name} declares unsupported role #{unsupported.first.inspect}"
        end

        ret
      end
    end

    class EventContext
      attr_reader :definition, :arguments
      attr_accessor :event, :route_context, :current_delivery

      def initialize(definition, arguments, event: nil)
        @definition = definition
        @arguments = arguments
        @event = event
      end

      def delivery(action)
        delivery_definition = definition.delivery(action)
        DeliveryContext.new(self, delivery_definition) if delivery_definition
      end

      def webui_url
        VpsAdmin::API::Events.webui_url
      end

      def payload
        event&.payload || {}
      end

      def param(name)
        name_s = name.to_s
        name_sym = name.to_sym
        if payload.has_key?(name_s)
          payload[name_s]
        elsif payload.has_key?(name_sym)
          payload[name_sym]
        end
      end

      def method_missing(name, *args, &block)
        return arguments.fetch(name) if args.empty? && block.nil? && arguments.has_key?(name)
        return definition.call_helper(self, name, *args) if definition.helper?(name)

        super
      end

      def respond_to_missing?(name, include_private = false)
        arguments.has_key?(name) || definition.helper?(name) || super
      end
    end

    class DeliveryContext
      def initialize(event_context, definition)
        @event_context = event_context
        @definition = definition
      end

      def template
        @definition&.evaluate_template(@event_context)
      end

      def params
        @definition&.evaluate_params(@event_context)
      end

      def vars
        @definition&.evaluate_vars(@event_context)
      end

      def options
        @definition&.evaluate_options(@event_context) || {}
      end

      def default_target
        @definition&.evaluate_default_target(@event_context)
      end

      def custom_target
        @definition&.evaluate_custom_target(@event_context)
      end

      def system_template?
        @definition&.evaluate_system_template(@event_context) == true
      end

      def custom_body
        @definition&.evaluate_custom_body(@event_context)
      end

      def custom_options
        @definition&.evaluate_custom_options(@event_context) || {}
      end
    end

    class DefinitionSet
      def initialize(owner)
        @owner = owner
      end

      def event(name, **, &block)
        definition = EventDefinition.new(name, owner: @owner, **)
        definition.instance_exec(&block) if block
        VpsAdmin::API::Events.add_definition(definition)
      end
    end

    RequestInfo = Struct.new(:ip)
    UserInfo = Struct.new(:id, :login, :full_name)
    VpsInfo = Struct.new(:id, :hostname, :user)
    ObjectStateInfo = Struct.new(:state, :reason, :expiration_date, :user)
    NodeInfo = Struct.new(:id, :domain_name)
    PoolInfo = Struct.new(:id, :filesystem)
    DnsResolverInfo = Struct.new(:id, :label, :addrs)
    DatasetInfo = Struct.new(:id, :full_name, :refquota, :referenced, :user)
    DatasetExpansionInfo = Struct.new(
      :id,
      :original_refquota,
      :added_space,
      :expansion_count,
      :over_refquota_seconds,
      :max_over_refquota_seconds,
      :enable_shrink
    )
    SnapshotInfo = Struct.new(:id, :name, :dataset)
    SnapshotDownloadInfo = Struct.new(:id, :file_name, :expiration_date, :user, :snapshot)
    VpsMigrationInfo = Struct.new(:id, :maintenance_window)
    RouteContext = Struct.new(
      :event,
      :route_owner,
      :subject_relation,
      :subject_user
    ) do
      def self.self_context(event)
        new(event, event.user, event.user_id.present? ? 'self' : 'system', event.user)
      end

      def self.for(event, route_owner)
        relation =
          if event.user_id.blank?
            'system'
          elsif route_owner && event.user_id == route_owner.id
            'self'
          else
            'other_user'
          end

        new(event, route_owner, relation, event.user)
      end

      def visible?
        event.visible_to?(route_owner)
      end

      def self_subject?
        subject_relation == 'self'
      end

      def system_subject?
        subject_relation == 'system'
      end

      def default_route_allowed?
        self_subject?
      end

      def source
        if system_subject?
          'system_route'
        elsif self_subject?
          'direct_route'
        else
          'visible_route'
        end
      end

      def subject_user_id
        subject_user&.id
      end

      def subject_is_self
        self_subject?
      end

      def subject_is_admin_visible
        !self_subject? && route_owner&.role == :admin
      end
    end
    RouteMatchPlan = Struct.new(
      :event_route,
      :route_context,
      :match_order,
      :time_interval_result
    )
    DeliveryPlan = Struct.new(
      :action,
      :target_kind,
      :target_value,
      :target_label,
      :template_name,
      :event_route,
      :notification_receiver,
      :notification_target,
      :notification_receiver_action,
      :state,
      :error_summary,
      :next_attempt_at,
      :payload,
      :route_context,
      :route_time_interval_state
    )

    RouteResult = Struct.new(
      :routing_state,
      :route_matches,
      :deliveries,
      :spent_event_routes,
      :routing_context_states
    ) do
      def releasable?
        deliveries.any? { |delivery| delivery.state != 'skipped' }
      end

      def persistable?
        releasable? || route_matches.any?
      end

      def suppressed_by_mute?
        routing_state == 'suppressed' &&
          deliveries.any? do |delivery|
            receiver = delivery.notification_receiver
            delivery.route_time_interval_state == 'muted' ||
              (delivery.route_time_interval_state == 'active' &&
                receiver&.enabled? && receiver.mute?)
          end
      end
    end

    @types = {}

    module_function

    def define(owner: nil, &)
      DefinitionSet.new(owner).instance_exec(&)
    end

    def add_definition(definition)
      @types[definition.name] = Type.new(
        name: definition.name,
        label: definition.label,
        category: definition.category_name,
        severity: definition.default_severity,
        roles: definition.roles,
        fields: definition.field_metadata,
        template: definition.template_name,
        default_routed: definition.default_routed,
        severity_description: definition.severity_description,
        definition:
      )
    end

    def types
      @types.values.sort_by(&:name)
    end

    def type_for(name)
      @types[name.to_s]
    end

    def default_routed?(name)
      type_for(name)&.default_routed == true
    end

    def type_labels
      types.to_h { |type| [type.name, type.label] }
    end

    def field_labels(event_type: nil)
      EventRouteMatcher.field_labels(event_type:)
    end

    def field_types(event_type: nil)
      EventRouteMatcher.field_types(event_type:)
    end

    def field_metadata(event_type: nil)
      EventRouteMatcher.field_metadata(event_type:)
    end

    def localized_type_label(type)
      I18n.t(
        "vpsadmin.events.types.#{i18n_key_fragment(type.name)}.label",
        default: type.label
      )
    end

    def localized_severity_description(type)
      return unless type.severity_description

      family = type.name.to_s.split('.', 2).first
      I18n.t(
        "vpsadmin.events.types.#{i18n_key_fragment(type.name)}.severity_description",
        default: I18n.t(
          "vpsadmin.events.types.#{family}.severity_description",
          default: type.severity_description
        )
      )
    end

    def localized_field_metadata(event_type:, field:)
      field = field.dup
      field_name = field.fetch(:name)
      family = event_type.to_s.split('.', 2).first
      field[:description] = I18n.t(
        "vpsadmin.events.fields.#{i18n_key_fragment(event_type)}.#{field_name}.description",
        default: I18n.t(
          "vpsadmin.events.fields.#{family}.#{field_name}.description",
          default: I18n.t(
            "vpsadmin.events.fields.common.#{field_name}.description",
            default: field.fetch(:description)
          )
        )
      )
      field
    end

    def i18n_key_fragment(value)
      value.to_s.tr('.', '_')
    end

    def i18n_defaults
      ret = {}

      EventRouteMatcher::COMMON_FIELDS.each do |name, config|
        ret["events.fields.common.#{name}.description"] = config.fetch(:description)
      end

      types.each do |type|
        type_key = i18n_key_fragment(type.name)
        ret["events.types.#{type_key}.label"] = type.label
        if type.severity_description
          ret["events.types.#{type_key}.severity_description"] = type.severity_description
        end

        type.fields.each do |field|
          field_key = field.fetch(:name)
          ret["events.fields.#{type_key}.#{field_key}.description"] = field.fetch(:description)
        end
      end

      if defined?(VpsAdmin::API::Plugins::Monitoring::Events) &&
         VpsAdmin::API::Plugins::Monitoring::Events.respond_to?(:i18n_defaults)
        ret.merge!(VpsAdmin::API::Plugins::Monitoring::Events.i18n_defaults)
      end

      ret
    end

    def matchable_field_values(event, route_context: nil)
      field_metadata(event_type: event.event_type).each_with_object({}) do |field, memo|
        name = field.fetch(:name)
        value = EventRouteMatcher.field_value(event, name, route_context:)
        memo[name] = value unless value.nil?
      end
    end

    def email_delivery_context_for(event, route_context: nil, delivery: nil)
      delivery_context_for_context(event, :email, route_context:, delivery:)
    end

    def sms_delivery_context_for(event, route_context: nil, delivery: nil)
      notification_delivery_context_for(event, :sms, route_context:, delivery:)
    end

    def telegram_delivery_context_for(event, route_context: nil, delivery: nil)
      notification_delivery_context_for(event, :telegram, route_context:, delivery:)
    end

    def notification_delivery_context_for(event, action, route_context: nil, delivery: nil)
      delivery_context_for_context(event, action, route_context:, delivery:) ||
        email_delivery_context_for(event, route_context:, delivery:)
    end

    def delivery_context_for(event, action)
      delivery_context_for_context(event, action)
    end

    def delivery_context_for_context(event, action, route_context: nil, delivery: nil)
      context = event.runtime_event_context ||
                type_for(event.event_type)&.definition&.build_context_from_event(event)
      return unless context

      context.route_context = route_context || route_context_for_delivery(delivery)
      context.current_delivery = delivery
      context.delivery(action)
    end

    def template_context_for(event, action, route_context: nil, delivery: nil)
      case action.to_s
      when 'sms'
        delivery_context_for_context(event, :sms, route_context:, delivery:) ||
          delivery_context_for_context(event, :email, route_context:, delivery:)
      when 'telegram'
        delivery_context_for_context(event, :telegram, route_context:, delivery:) ||
          delivery_context_for_context(event, :email, route_context:, delivery:)
      else
        delivery_context_for_context(event, action, route_context:, delivery:)
      end
    end

    def template_name_for(event, action = :email, route_context: nil, delivery: nil)
      template_context_for(event, action, route_context:, delivery:)&.template&.to_sym
    end

    def template_params_for(event, action = :email, route_context: nil, delivery: nil)
      template_context_for(event, action, route_context:, delivery:)&.params
    end

    def template_options_for(event, delivery = nil, action: nil)
      action ||= delivery&.action || :email
      opts = {
        user: delivery&.recipient_user || event.user,
        vars: template_vars_for(event, action, delivery:)
      }
      template_params = template_params_for(event, action, delivery:)
      opts[:params] = template_params if template_params

      if delivery&.email_action?
        opts[:to] = email_target_addresses(event, delivery)
        opts[:include_default_recipients] = false
        opts[:include_template_recipients] = false
      end

      opts.merge!(template_extra_options_for(event, action, delivery:))
      opts
    end

    def email_custom_options_for(event, delivery)
      {
        user: delivery&.recipient_user || event.user,
        from: NotificationTemplates.default_from,
        to: email_target_addresses(event, delivery),
        subject: event.subject,
        text_plain: custom_email_body(event, delivery)
      }.merge(custom_email_extra_options_for(event, delivery:))
    end

    def email_target_addresses(event, delivery)
      if delivery.default_recipient_target_kind?
        address = delivery.target_value.presence
        address = nil if address == 'default'
        address ||= delivery.recipient_user&.email || event.user&.email
        raise ArgumentError, 'event has no user e-mail recipient' if address.blank?

        return [address]
      end

      addresses = delivery.target_value.to_s.split(',').map(&:strip).reject(&:blank?)
      raise ArgumentError, 'e-mail delivery has no recipient address' if addresses.empty?

      addresses
    end

    def template_vars_for(event, action = :email, route_context: nil, delivery: nil)
      {
        event:,
        notification_event: event,
        user: event.user,
        payload: event.payload || {}
      }.merge(template_context_for(event, action, route_context:, delivery:)&.vars || {})
    end

    def template_extra_options_for(event, action = :email, route_context: nil, delivery: nil)
      template_context_for(event, action, route_context:, delivery:)&.options || {}
    end

    def custom_email_extra_options_for(event, route_context: nil, delivery: nil)
      email_delivery_context_for(event, route_context:, delivery:)&.custom_options || {}
    end

    def template_available?(name, params, language, protocol: 'email')
      resolved_name = ::NotificationTemplate.resolve_name(name, params)
      template = ::NotificationTemplate.find_by(name: resolved_name)
      return false unless template
      return true unless language

      ::NotificationTemplate.find_variant(template, language, protocol).present?
    rescue StandardError
      false
    end

    def explicit_default_target?(delivery)
      delivery.default_recipient_target_kind? &&
        delivery.target_value.present? &&
        delivery.target_value != 'default'
    end

    def default_email_target_for(event, route_context: nil, delivery: nil)
      email_delivery_context_for(event, route_context:, delivery:)&.default_target
    end

    def custom_email_target_for(event, route_context: nil, delivery: nil)
      email_delivery_context_for(event, route_context:, delivery:)&.custom_target
    end

    def system_template_email?(event, route_context: nil, delivery: nil)
      email_delivery_context_for(event, route_context:, delivery:)&.system_template? == true
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def route_context_for_delivery(delivery)
      return unless delivery

      routing_context = delivery.event_routing_context
      return unless routing_context

      RouteContext.new(
        delivery.event,
        routing_context.recipient_user,
        routing_context.subject_relation,
        delivery.event.user
      )
    end

    def custom_email_body(event, delivery)
      body = email_delivery_context_for(event, delivery:)&.custom_body
      return body if body.present?

      ret = [
        event.summary.presence,
        "Event type: #{event.event_type}",
        "Severity: #{event.severity}",
        event.vps && "VPS: ##{event.vps.id} #{event.vps.hostname}",
        event.ip_addr && "IP address: #{event.ip_addr}",
        "Payload:\n#{JSON.pretty_generate(event.payload || {})}"
      ].compact

      ret.join("\n\n")
    end

    def webui_url
      (::SysConfig.get(:webui, :base_url) || '').chomp('/')
    rescue StandardError
      ''
    end

    def field?(field)
      EventRouteMatcher.field?(field)
    end

    def plan(event_type, user: nil, vps: nil, subject: nil, summary: nil,
             payload: nil, severity: nil, category: nil, ip_addr: nil,
             occurred_at: nil, record_route_hits: false, **event_args)
      type = type_for(event_type)
      context = event_context_for(type, event_args)
      attrs = context ? type.definition.build_attributes(context) : {}
      if user && vps && vps.user_id != user.id
        raise ArgumentError, 'user and VPS owner do not match'
      end

      user ||= attrs[:user]
      vps ||= attrs[:vps]
      owner = user || vps&.user
      event = ::Event.new(
        user: owner,
        vps:,
        event_type: event_type.to_s,
        category: category || attrs[:category] || type&.category || 'general',
        severity: severity || attrs[:severity] || type&.severity || 'info',
        subject: subject || attrs[:subject] || type&.label || event_type.to_s,
        summary: summary || attrs[:summary],
        parameters: payload_with_defaults(type, payload || attrs[:payload] || {}),
        ip_addr: ip_addr || attrs[:ip_addr],
        created_at: occurred_at
      )
      context.event = event if context
      event.runtime_event_context = context

      Router.new(event).plan(record_route_hits:)
    end

    def emit!(event_type, user: nil, vps: nil, source: nil, source_class: nil,
              source_id: nil, subject: nil, summary: nil, payload: nil,
              severity: nil, category: nil, ip_addr: nil, route: true,
              release: true, persist: :routed, route_context_mode: nil,
              route_owner: nil, **event_args)
      type = type_for(event_type)
      context = event_context_for(type, event_args)
      attrs = context ? type.definition.build_attributes(context) : {}
      if user && vps && vps.user_id != user.id
        raise ArgumentError, 'user and VPS owner do not match'
      end

      user ||= attrs[:user]
      vps ||= attrs[:vps]
      source ||= attrs[:source]
      owner = user || vps&.user

      event = ::Event.new(
        user: owner,
        vps:,
        event_type: event_type.to_s,
        category: category || attrs[:category] || type&.category,
        severity: severity || attrs[:severity] || type&.severity,
        subject: subject || attrs[:subject] || type&.label,
        summary: summary || attrs[:summary],
        parameters: payload_with_defaults(type, payload || attrs[:payload] || {}),
        source_class: source_class || source&.class&.name,
        source_id: source_id || source&.id,
        ip_addr: ip_addr || attrs[:ip_addr]
      )
      context.event = event if context
      event.runtime_event_context = context

      if route
        router = Router.new(
          event,
          route_context_mode:,
          route_owner:
        )
        result = router.plan

        return nil if persist != :always && !result.persistable?

        router.persist!(result)
        VpsAdmin::API::Notifications::Release.release!(event.event_deliveries.where(state: 'prepared')) if release
      else
        event.save!
      end

      event
    end

    def event_context_for(type, event_args)
      return if event_args.empty?
      raise ArgumentError, "event does not accept typed arguments: #{event_args.keys.join(', ')}" unless type&.definition

      type.definition.build_context(event_args)
    end

    def payload_with_defaults(type, payload)
      ret = (payload || {}).dup
      if type&.roles && !ret.has_key?(:roles) && !ret.has_key?('roles')
        ret[:roles] = type.roles
      end
      ret
    end

    def route!(event)
      Router.new(event).route!
    end

    def emit_transaction_chain_state!(chain, previous_state: nil, state: nil,
                                      changed_at: nil, node: nil)
      state ||= chain.state
      return unless state

      emit!(
        'transaction_chain.state_changed',
        user: chain.user,
        source: chain,
        source_class: ::TransactionChain.name,
        subject: transaction_chain_subject(chain, state),
        summary: transaction_chain_summary(chain, previous_state, state),
        severity: TRANSACTION_CHAIN_STATE_SEVERITIES.fetch(state.to_s, 'info'),
        payload: transaction_chain_parameters(
          chain,
          previous_state:,
          state:,
          changed_at:,
          node:
        )
      )
    end

    def transaction_chain_parameters(chain, previous_state:, state:, changed_at: nil, node: nil)
      terminal = TRANSACTION_CHAIN_TERMINAL_STATES.include?(state.to_s)
      failed = TRANSACTION_CHAIN_FAILED_STATES.include?(state.to_s)
      event_time = changed_at || Time.now
      concerns = safe_transaction_chain_concerns(chain)
      concern_objects = Array(concerns[:objects] || concerns['objects'])

      {
        chain_id: chain.id,
        chain_name: chain.name,
        chain_label: safe_transaction_chain_label(chain),
        previous_state:,
        state:,
        terminal:,
        successful: terminal && !failed,
        failed:,
        size: chain.size,
        progress: chain.progress,
        user_session_id: chain.user_session_id,
        concerns:,
        concern_classes: concern_objects.map { |item| Array(item).first }.compact.uniq,
        concern_object_ids: concern_objects.map { |item| Array(item)[1] }.compact,
        node_id: node&.id,
        node_name: node&.domain_name,
        changed_at: event_time.iso8601,
        changed_at_timestamp: event_time.to_f
      }.compact
    end

    def transaction_chain_subject(chain, state)
      "Transaction chain ##{chain.id} #{safe_transaction_chain_label(chain)} #{state}".strip[0, 255]
    end

    def transaction_chain_summary(chain, previous_state, state)
      previous = previous_state.present? ? "#{previous_state} -> " : ''
      "#{safe_transaction_chain_label(chain)} changed state to #{previous}#{state}"
    end

    def safe_transaction_chain_label(chain)
      chain.label
    rescue StandardError
      chain.name
    end

    def safe_transaction_chain_concerns(chain)
      chain.format_concerns
    rescue StandardError
      { type: nil, objects: [] }
    end

    def emit_dns_transfer_event!(log, previous_status:)
      return unless user_visible_dns_transfer?(log)

      event_type =
        if log.failed?
          'dns.zone_transfer.failed'
        elsif log.success? && previous_status.to_s == 'failed'
          'dns.zone_transfer.recovered'
        end
      return unless event_type

      zone = log.dns_server_zone.dns_zone
      server = log.dns_server_zone.dns_server
      emit!(
        event_type,
        user: zone.user,
        source: log,
        subject: dns_transfer_subject(log),
        summary: dns_transfer_summary(log),
        severity: log.failed? ? 'warning' : 'info',
        payload: dns_transfer_parameters(log, previous_status:)
      )
    end

    def user_visible_dns_transfer?(log)
      server_zone = log.dns_server_zone
      zone = server_zone&.dns_zone
      server = server_zone&.dns_server

      zone&.external_source? && zone.user_id.present? && server && !server.hidden
    end

    def dns_transfer_parameters(log, previous_status:)
      server_zone = log.dns_server_zone
      zone = server_zone.dns_zone
      server = server_zone.dns_server
      node = server.node

      {
        transfer_log_id: log.id,
        dns_zone_id: zone.id,
        dns_zone_name: zone.name,
        dns_server_zone_id: server_zone.id,
        dns_server_id: server.id,
        dns_server_name: server.name,
        node_id: node&.id,
        node_name: node&.domain_name,
        previous_status:,
        status: log.status,
        reason_code: log.reason_code,
        reason: log.reason,
        primary_addr: log.primary_addr,
        serial: log.serial,
        message: log.message,
        event_at: log.event_at&.iso8601
      }.compact
    end

    def dns_transfer_subject(log)
      zone = log.dns_server_zone.dns_zone
      if log.failed?
        "DNS transfer failed for #{zone.name}"[0, 255]
      else
        "DNS transfer recovered for #{zone.name}"[0, 255]
      end
    end

    def dns_transfer_summary(log)
      if log.failed?
        [log.reason_code, log.reason, log.message].compact.join(': ')
      else
        log.message.presence || 'DNS zone transfer succeeded after a previous failure'
      end
    end

    class Router
      attr_reader :event

      def initialize(event, route_context_mode: nil, route_owner: nil)
        @event = event
        @route_context_mode = route_context_mode&.to_sym
        @route_owner = route_owner
        @matched_routes = []
        @matched_route_matches = []
        @match_order = 0
        @event_time = event.created_at || Time.now
      end

      def route!
        persist!(plan)
      end

      def persist!(result)
        event.class.transaction do
          if event.persisted?
            event.lock!
            event.event_deliveries.delete_all
            event.event_routing_contexts.delete_all
            event.event_route_matches.delete_all
            event.update!(
              routing_state: result.routing_state
            )
          else
            event.routing_state = result.routing_state
            event.save!
          end

          result.route_matches.each do |route_match|
            create_route_match!(route_match)
          end

          result.deliveries.each do |delivery|
            create_delivery!(delivery, result.routing_context_states)
          end

          record_route_hits!
          spend_single_use_routes(result.spent_event_routes)
        end

        event
      end

      def plan(record_route_hits: false)
        ensure_default_routes
        plan_all_contexts.tap do
          record_route_hits! if record_route_hits
        end
      end

      protected

      def ensure_default_routes
        ::NotificationReceiver.ensure_admin_request_defaults! if request_event?
        return unless event.user

        ::NotificationReceiver.ensure_defaults_for!(event.user)
      end

      def request_event?
        event.event_type.to_s.start_with?('request.')
      end

      def plan_all_contexts
        context_results = route_contexts.map do |route_context|
          plan_route(route_context, emit_skipped: route_context.self_subject?)
        end

        deliveries = deduplicate(context_results.flat_map(&:deliveries) + direct_email_deliveries)

        RouteResult.new(
          routing_state: routing_state_for(deliveries),
          route_matches: @matched_route_matches,
          deliveries:,
          spent_event_routes: context_results.flat_map(&:spent_event_routes).uniq,
          routing_context_states: routing_context_states(deliveries)
        )
      end

      def route_contexts
        return [] if @route_context_mode == :self && event.user.nil?
        return [RouteContext.for(event, event.user)] if @route_context_mode == :self
        return @route_owner ? [RouteContext.for(event, @route_owner)] : [] if @route_context_mode == :route_owner

        ret = []
        ret << RouteContext.for(event, event.user) if event.user

        admin_route_owner_ids.each do |user_id|
          next if event.user_id.present? && event.user_id == user_id

          owner = admin_route_owners.fetch(user_id)
          ret << RouteContext.for(event, owner)
        end

        ret
      end

      def direct_email_deliveries
        return [] unless event.user_id.blank?
        return [] unless VpsAdmin::API::Notifications::Actions.known?('email')

        custom_target = VpsAdmin::API::Events.custom_email_target_for(event).presence
        if custom_target
          return [
            direct_email_delivery(
              target_kind: 'custom',
              target_value: custom_target,
              target_label: custom_target
            )
          ]
        end

        default_target = VpsAdmin::API::Events.default_email_target_for(event).presence
        return [] unless default_target

        [
          direct_email_delivery(
            target_kind: 'default_recipient',
            target_value: default_target,
            target_label: default_target,
            template_name: VpsAdmin::API::Events.template_name_for(event, :email)
          )
        ]
      end

      def admin_route_owner_ids
        @admin_route_owner_ids ||= begin
          scope = ::EventRoute
                  .active
                  .where(enabled: true, subject_scope: ::EventRoute.subject_scopes.fetch('visible'))
                  .where(
                    'event_type IS NULL OR event_type = ? OR event_type_pattern IS NOT NULL',
                    event.event_type
                  )
          user_ids = scope.distinct.pluck(:user_id)
          user_ids &= admin_route_owners.keys
          user_ids.sort
        end
      end

      def admin_route_owners
        @admin_route_owners ||= ::User.where(level: 90..).index_by(&:id)
      end

      def plan_route(route_context, emit_skipped:)
        deadline = monotonic_time + EVALUATION_TIMEOUT
        deliveries = []
        previous_route_context = @route_context
        @route_context = route_context

        child_routes(route_context, nil).each do |route|
          break if deadline_expired?(deadline)
          next unless route.matches_in_context?(route_context, deadline:)

          deliveries.concat(process_route(route_context, route, deadline))

          break unless route.continue?
        end

        deliveries = [skipped_delivery(nil, nil, nil, 'no route matched the event')] if deliveries.empty? && emit_skipped

        RouteResult.new(
          routing_state: routing_state_for(deliveries),
          route_matches: [],
          deliveries:,
          spent_event_routes: spent_routes
        )
      ensure
        @route_context = previous_route_context
      end

      def process_route(route_context, route, deadline)
        time_interval_result = record_matched_route(route_context, route)

        deliveries =
          if route.notification_receiver.nil?
            []
          elsif time_interval_result.fetch('state') == 'active'
            deliveries_for_route(route)
          else
            deliveries_for_scheduled_route(route, time_interval_result.fetch('state'))
          end
        matched_child = false

        child_routes(route_context, route.id).each do |child|
          break if deadline_expired?(deadline)
          next unless child.matches_in_context?(route_context, deadline:)

          matched_child = true
          deliveries.concat(process_route(route_context, child, deadline))

          break unless child.continue?
        end

        if deliveries.empty? && !matched_child && route.notification_receiver.nil?
          return [skipped_delivery(route, nil, nil, 'route has no receiver')]
        end

        deliveries
      end

      def child_routes(route_context, parent_id)
        routes_by_parent(route_context.route_owner)[parent_id] || []
      end

      def routes_by_parent(route_owner)
        return {} unless route_owner

        @routes_by_parent ||= {}
        @routes_by_parent[route_owner.id] ||=
          route_owner.event_routes
                     .active
                     .where(enabled: true)
                     .includes(
                       :event_route_matchers,
                       event_route_time_intervals: :event_time_interval,
                       notification_receiver: [
                         { notification_receiver_actions: :notification_target },
                         { user: :user_notification_delivery_methods }
                       ]
                     )
                     .order(:position, :id)
                     .to_a
                     .group_by(&:parent_id)
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

        actions = receiver.notification_receiver_actions.to_a

        if actions.empty?
          return [skipped_delivery(route, receiver, nil, 'receiver has no linked targets')]
        end

        actions.map { |receiver_action| delivery_from_receiver_action(route, receiver, receiver_action) }
      end

      def deliveries_for_scheduled_route(route, state)
        receiver = route.notification_receiver
        reason =
          if state == 'muted'
            'route is muted by a time interval'
          else
            'route is outside its active time intervals'
          end
        actions = receiver.notification_receiver_actions.to_a

        return [skipped_delivery(route, receiver, nil, reason, route_time_interval_state: state)] if actions.empty?

        actions.map do |receiver_action|
          skipped_delivery(
            route,
            receiver,
            receiver_action,
            reason,
            route_time_interval_state: state
          )
        end
      end

      def delivery_from_receiver_action(route, receiver, receiver_action)
        unless VpsAdmin::API::Notifications::Actions.known?(receiver_action.action)
          return skipped_delivery(route, receiver, receiver_action, 'unknown receiver target')
        end

        unless receiver_action.action_available?
          return skipped_delivery(route, receiver, receiver_action, 'receiver target is not available')
        end

        unless receiver_action.delivery_method_enabled?
          return skipped_delivery(route, receiver, receiver_action, 'delivery method is disabled')
        end

        unless receiver_action.deliverable?
          return skipped_delivery(route, receiver, receiver_action, 'receiver target is disabled')
        end

        VpsAdmin::API::Notifications::Actions
          .fetch(receiver_action.action)
          .plan_delivery_for(self, route, receiver, receiver_action)
      end

      def email_delivery(route, receiver, receiver_action)
        if receiver_action.email_verification_required? && !receiver_action.verified?
          return skipped_delivery(route, receiver, receiver_action, 'e-mail target is not verified')
        end

        if receiver_action.default_recipient_target_kind?
          if @route_context&.route_owner.nil?
            return skipped_delivery(route, receiver, receiver_action, 'route has no recipient user')
          end

          if @route_context&.self_subject?
            target = VpsAdmin::API::Events.default_email_target_for(
              event,
              route_context: @route_context
            )
          end
          return build_delivery(
            route,
            receiver,
            receiver_action,
            target_value: target.presence || 'default',
            target_label: target.present? ? target : 'Default recipient'
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

      def webhook_delivery(route, receiver, receiver_action)
        return skipped_delivery(route, receiver, receiver_action, 'webhook URL is not configured') if receiver_action.target_value.blank?

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.label
        )
      end

      def telegram_delivery(route, receiver, receiver_action)
        return skipped_delivery(route, receiver, receiver_action, 'Telegram chat is not linked') if receiver_action.target_value.blank?
        return skipped_delivery(route, receiver, receiver_action, 'Telegram chat is not verified') unless receiver_action.verified?

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.display_target
        )
      end

      def sms_delivery(route, receiver, receiver_action)
        return skipped_delivery(route, receiver, receiver_action, 'SMS number is not configured') if receiver_action.target_value.blank?
        return skipped_delivery(route, receiver, receiver_action, 'SMS number is not verified') unless receiver_action.verified?

        build_delivery(
          route,
          receiver,
          receiver_action,
          target_value: receiver_action.target_value,
          target_label: receiver_action.display_target
        )
      end

      def build_delivery(route, receiver, receiver_action, target_value:, target_label:, template_name: nil,
                         target_kind: nil, state: 'prepared', next_attempt_at: nil, payload: nil)
        DeliveryPlan.new(
          action: receiver_action&.action || 'email',
          target_kind: target_kind || receiver_action&.target_kind || 'default_recipient',
          target_value:,
          target_label: delivery_label(target_label),
          template_name: template_name || delivery_template_name(route, receiver_action),
          event_route: route,
          notification_receiver: receiver,
          notification_target: receiver_action&.notification_target,
          notification_receiver_action: receiver_action,
          state:,
          next_attempt_at:,
          payload:,
          route_context: @route_context,
          route_time_interval_state: 'active'
        )
      end

      def direct_email_delivery(target_kind:, target_value:, target_label:, template_name: nil)
        DeliveryPlan.new(
          action: 'email',
          target_kind:,
          target_value:,
          target_label: delivery_label(target_label),
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

      def skipped_delivery(route, receiver, receiver_action, reason, route_time_interval_state: 'active')
        DeliveryPlan.new(
          action: receiver_action&.action || 'email',
          target_kind: receiver_action&.target_kind || 'default_recipient',
          target_value: receiver_action&.target_value,
          target_label: delivery_label(receiver_action&.display_target || receiver&.label),
          template_name: delivery_template_name(route, receiver_action),
          event_route: route,
          notification_receiver: receiver,
          notification_target: receiver_action&.notification_target,
          notification_receiver_action: receiver_action,
          state: 'skipped',
          error_summary: reason,
          route_context: @route_context,
          route_time_interval_state:
        )
      end

      def delivery_label(label)
        return if label.nil?

        label.to_s[0, DELIVERY_LABEL_LIMIT]
      end

      def delivery_template_name(route, receiver_action)
        return unless receiver_action.nil? ||
                      receiver_action.email_action? ||
                      receiver_action.telegram_action? ||
                      receiver_action.sms_action?

        route_template_name = route&.template_name.presence
        return route_template_name if route_template_name
        return unless receiver_action&.email_action? ||
                      receiver_action&.telegram_action? ||
                      receiver_action&.sms_action?

        VpsAdmin::API::Events.template_name_for(
          event,
          receiver_action.action,
          route_context: @route_context
        )
      end

      def routing_state_for(deliveries)
        return 'suppressed' if deliveries.empty?

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
            delivery.route_context&.route_owner&.id,
            delivery.state,
            delivery.event_route&.id,
            delivery.notification_receiver&.id,
            delivery.notification_target&.id,
            delivery.notification_receiver_action&.id,
            delivery.error_summary
          ]
        end

        target_key =
          if delivery.notification_target
            [:target, delivery.notification_target.id]
          else
            [:value, delivery.target_value]
          end

        [
          delivery.route_context&.route_owner&.id,
          delivery.action,
          delivery.target_kind,
          target_key,
          delivery.template_name,
          delivery.state
        ]
      end

      def routing_context_states(deliveries)
        deliveries.select { |delivery| delivery.route_context&.route_owner }.group_by do |delivery|
          delivery.route_context.route_owner.id
        end.transform_values do |items|
          if items.any? { |delivery| delivery.state == 'failed' }
            'failed'
          elsif items.any? { |delivery| delivery.state != 'skipped' }
            'routed'
          else
            'suppressed'
          end
        end
      end

      def create_delivery!(delivery, routing_context_states)
        routing_context =
          if delivery.route_context&.route_owner
            routing_context_for_delivery(
              delivery,
              routing_context_states.fetch(delivery.route_context.route_owner.id)
            )
          end
        record = event.event_deliveries.create!(
          event_routing_context: routing_context,
          event_route: delivery.event_route,
          notification_receiver: delivery.notification_receiver,
          notification_target: delivery.notification_target,
          notification_receiver_action: delivery.notification_receiver_action,
          action: delivery.action,
          target_kind: delivery.target_kind,
          target_value: delivery.target_value,
          target_label: delivery.target_label,
          template_name: delivery.template_name,
          state: delivery.state,
          error_summary: delivery.error_summary,
          next_attempt_at: delivery.next_attempt_at,
          payload: delivery.payload
        )

        record.association(:event).target = event if event.runtime_email_context?

        if record.prepared_state?
          VpsAdmin::API::Notifications::Actions
            .fetch(record.action)
            .prepare_delivery_for(self, record)
        end

        record
      end

      def create_route_match!(route_match)
        route_context = route_match.route_context

        event.event_route_matches.create!(
          event_route: route_match.event_route,
          route_owner: route_context.route_owner,
          subject_relation: route_context.subject_relation,
          source: route_context.source,
          match_order: route_match.match_order,
          time_interval_state: route_match.time_interval_result.fetch('state'),
          time_interval_snapshot: route_match.time_interval_result
        )
      end

      def routing_context_for_delivery(delivery, routing_state)
        route_context = delivery.route_context
        user = route_context.route_owner

        event.event_routing_contexts.find_or_create_by!(user_id: user.id) do |context|
          context.subject_relation = route_context.subject_relation
          context.source = route_context.source
          context.routing_state = routing_state
        end.tap do |context|
          attrs = {}
          attrs[:routing_state] = routing_state if context.routing_state != routing_state
          context.update!(attrs) if attrs.any?
        end
      end

      def spent_routes
        @matched_routes.select(&:single_use?).uniq
      end

      def record_route_hits!
        @matched_routes.uniq.each do |route|
          ::EventRoute.increment_counter(:hit_count, route.id)
        end
      end

      def record_matched_route(route_context, route)
        @matched_routes << route
        @match_order += 1
        result = route.time_interval_result(at: @event_time)
        @matched_route_matches << RouteMatchPlan.new(route, route_context, @match_order, result)
        result
      end

      def spend_single_use_routes(routes)
        routes.each(&:spend!)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def deadline_expired?(deadline)
        monotonic_time >= deadline
      end
    end
  end
end

require_relative 'events/core'
