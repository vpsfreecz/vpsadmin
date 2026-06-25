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

    Type = Struct.new(
      :name,
      :label,
      :category,
      :severity,
      :parameters,
      :template,
      :default_routed,
      :severity_description,
      :definition
    )

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
                  :default_routed, :severity_description,
                  :arguments, :parameter_labels

      def initialize(name, label:, category:, default_routed:, owner: nil,
                     severity: :info, template: nil,
                     severity_description: nil)
        @name = name.to_s
        @owner = owner
        @label = label
        @category_name = category.to_s
        @default_severity = severity.to_s
        @default_routed = default_routed ? true : false
        @severity_description = severity_description
        @fallback_template_name = template&.to_s
        @arguments = {}
        @parameter_labels = {}
        @parameter_blocks = {}
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

      def parameter(name, label, &block)
        @parameter_labels[name.to_sym] = label
        @parameter_blocks[name.to_sym] = block if block
      end

      def parameters(hash)
        hash.each { |name, label| parameter(name, label) }
      end

      def extra_parameters(&block)
        @extra_parameters_block = block
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
          parameters: build_parameters(context)
        }.compact
      end

      def template_name
        delivery(:email)&.static_template_name || @fallback_template_name
      end

      protected

      def build_parameters(context)
        ret = @parameter_blocks.each_with_object({}) do |(name, block), memo|
          value = context.instance_exec(&block)
          memo[name] = value unless value.nil?
        end
        extra = context.instance_exec(&@extra_parameters_block) if @extra_parameters_block
        ret.merge!(extra || {})
        ret
      end

      def evaluate(context, block)
        context.instance_exec(&block) if block
      end
    end

    class EventContext
      attr_reader :definition, :arguments
      attr_accessor :event

      def initialize(definition, arguments, event: nil)
        @definition = definition
        @arguments = arguments
        @event = event
      end

      def delivery(action)
        DeliveryContext.new(self, definition.delivery(action))
      end

      def webui_url
        VpsAdmin::API::Events.webui_url
      end

      def parameters
        event&.parameters || {}
      end

      def param(name)
        parameters[name.to_s] || parameters[name.to_sym]
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
      :payload
    )

    RouteResult = Struct.new(
      :routing_state,
      :matched_event_route,
      :deliveries,
      :spent_event_routes
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

    def define(owner: nil, &)
      DefinitionSet.new(owner).instance_exec(&)
    end

    def add_definition(definition)
      @types[definition.name] = Type.new(
        name: definition.name,
        label: definition.label,
        category: definition.category_name,
        severity: definition.default_severity,
        parameters: definition.parameter_labels,
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

    def email_delivery_context_for(event)
      delivery_context_for(event, :email)
    end

    def sms_delivery_context_for(event)
      delivery_context_for(event, :sms) || email_delivery_context_for(event)
    end

    def delivery_context_for(event, action)
      context = event.runtime_event_context ||
                type_for(event.event_type)&.definition&.build_context_from_event(event)
      return unless context

      context.delivery(action)
    end

    def template_context_for(event, action)
      action.to_s == 'sms' ? sms_delivery_context_for(event) : delivery_context_for(event, action)
    end

    def template_name_for(event, action = :email)
      template_context_for(event, action)&.template&.to_sym
    end

    def template_params_for(event, action = :email)
      template_context_for(event, action)&.params
    end

    def template_options_for(event, delivery = nil, action: nil)
      action ||= delivery&.action || :email
      opts = {
        user: event.user,
        vars: template_vars_for(event, action)
      }
      template_params = template_params_for(event, action)
      opts[:params] = template_params if template_params

      if delivery&.email_action? && delivery.custom_target_kind?
        opts[:to] = email_target_addresses(event, delivery)
        opts[:include_default_recipients] = false
        opts[:include_template_recipients] = false
      elsif delivery&.email_action? && explicit_default_target?(delivery)
        opts[:to] = email_target_addresses(event, delivery)
      end

      opts.merge!(template_extra_options_for(event, action))
      opts
    end

    def email_custom_options_for(event, delivery)
      {
        user: event.user,
        from: NotificationTemplates.default_from,
        to: email_target_addresses(event, delivery),
        subject: event.subject,
        text_plain: custom_email_body(event, delivery)
      }.merge(custom_email_extra_options_for(event))
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

    def template_vars_for(event, action = :email)
      {
        event:,
        user: event.user,
        parameters: event.parameters || {}
      }.merge(template_context_for(event, action)&.vars || {})
    end

    def template_extra_options_for(event, action = :email)
      template_context_for(event, action)&.options || {}
    end

    def custom_email_extra_options_for(event)
      email_delivery_context_for(event)&.custom_options || {}
    end

    def template_available?(name, params, language, protocol: 'email')
      resolved_name = ::NotificationTemplate.resolve_name(name, params)
      template = ::NotificationTemplate.find_by(name: resolved_name)
      return false unless template
      return true unless language

      template.notification_template_variants.where(language:, protocol:).exists?
    rescue StandardError
      false
    end

    def explicit_default_target?(delivery)
      delivery.default_recipient_target_kind? &&
        delivery.target_value.present? &&
        delivery.target_value != 'default'
    end

    def default_email_target_for(event)
      email_delivery_context_for(event)&.default_target
    end

    def custom_email_target_for(event)
      email_delivery_context_for(event)&.custom_target
    end

    def system_template_email?(event)
      email_delivery_context_for(event)&.system_template? == true
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def custom_email_body(event, delivery)
      body = email_delivery_context_for(event)&.custom_body
      return body if body.present?

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

    def webui_url
      (::SysConfig.get(:webui, :base_url) || '').chomp('/')
    rescue StandardError
      ''
    end

    def parameter_field?(field)
      return false unless field.to_s.start_with?('parameters.')

      name = field.to_s.delete_prefix('parameters.')
      types.any? { |type| type.parameters.has_key?(name.to_sym) || type.parameters.has_key?(name) }
    end

    def plan(event_type, user: nil, vps: nil, subject: nil, summary: nil,
             parameters: nil, severity: nil, category: nil, ip_addr: nil,
             **event_args)
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
        parameters: parameters || attrs[:parameters] || {},
        ip_addr: ip_addr || attrs[:ip_addr]
      )
      context.event = event if context
      event.runtime_event_context = context

      Router.new(event).plan
    end

    def emit!(event_type, user: nil, vps: nil, source: nil, source_class: nil,
              source_id: nil, subject: nil, summary: nil, parameters: nil,
              severity: nil, category: nil, ip_addr: nil, route: true,
              release: true, **event_args)
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

      event = ::Event.create!(
        user: owner,
        vps:,
        event_type: event_type.to_s,
        category: category || attrs[:category] || type&.category,
        severity: severity || attrs[:severity] || type&.severity,
        subject: subject || attrs[:subject] || type&.label,
        summary: summary || attrs[:summary],
        parameters: parameters || attrs[:parameters] || {},
        source_class: source_class || source&.class&.name,
        source_id: source_id || source&.id,
        ip_addr: ip_addr || attrs[:ip_addr]
      )
      context.event = event if context
      event.runtime_event_context = context

      route!(event) if route
      VpsAdmin::API::Notifications::Release.release!(event.event_deliveries.where(state: 'prepared')) if route && release

      event
    end

    def event_context_for(type, event_args)
      return if event_args.empty?
      raise ArgumentError, "event does not accept typed arguments: #{event_args.keys.join(', ')}" unless type&.definition

      type.definition.build_context(event_args)
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
        parameters: transaction_chain_parameters(
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
        concerns: safe_transaction_chain_concerns(chain),
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
        parameters: dns_transfer_parameters(log, previous_status:)
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

      def initialize(event)
        @event = event
        @matched_routes = []
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

          spend_single_use_routes(result.spent_event_routes)
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
          deliveries = direct_deliveries
          deliveries = [skipped_delivery(nil, nil, nil, 'no route matched the event')] if deliveries.empty?
        end

        first_delivery_route = deliveries.map(&:event_route).compact.first

        RouteResult.new(
          routing_state: routing_state_for(deliveries),
          matched_event_route: first_delivery_route || first_matched_route,
          deliveries: deduplicate(deliveries),
          spent_event_routes: spent_routes
        )
      end

      def process_route(route, deadline)
        ::EventRoute.increment_counter(:hit_count, route.id)
        @matched_routes << route

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

      def direct_deliveries
        return [] if event.user

        target = VpsAdmin::API::Events.default_email_target_for(event)
        custom_target = VpsAdmin::API::Events.custom_email_target_for(event)
        if custom_target.present?
          return [
            build_delivery(
              nil,
              nil,
              nil,
              target_kind: 'custom',
              target_value: custom_target,
              target_label: custom_target,
              template_name: VpsAdmin::API::Events.template_name_for(event),
              state: 'prepared'
            )
          ]
        end

        if target.blank?
          return [] unless VpsAdmin::API::Events.system_template_email?(event)

          return [
            build_delivery(
              nil,
              nil,
              nil,
              target_value: nil,
              target_label: 'Template recipients',
              template_name: VpsAdmin::API::Events.template_name_for(event),
              state: 'prepared'
            )
          ]
        end

        [
          build_delivery(
            nil,
            nil,
            nil,
            target_value: target,
            target_label: target,
            template_name: VpsAdmin::API::Events.template_name_for(event),
            state: 'prepared'
          )
        ]
      end

      def child_routes(parent_id)
        routes_by_parent[parent_id] || []
      end

      def routes_by_parent
        @routes_by_parent ||= if event.user
                                event.user.event_routes
                                     .active
                                     .where(enabled: true)
                                     .includes(
                                       :event_route_matchers,
                                       notification_receiver: [
                                         { notification_receiver_actions: :notification_target },
                                         { user: :user_notification_delivery_methods }
                                       ]
                                     )
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

        actions = receiver.notification_receiver_actions.to_a

        if actions.empty?
          return [skipped_delivery(route, receiver, nil, 'receiver has no linked targets')]
        end

        actions.map { |receiver_action| delivery_from_receiver_action(route, receiver, receiver_action) }
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
          if event.user.nil?
            return skipped_delivery(route, receiver, receiver_action, 'event has no user')
          end

          target = VpsAdmin::API::Events.default_email_target_for(event)
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
          payload:
        )
      end

      def skipped_delivery(route, receiver, receiver_action, reason)
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
          error_summary: reason
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

        VpsAdmin::API::Events.template_name_for(event, receiver_action.action)
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
          delivery.action,
          delivery.target_kind,
          target_key,
          delivery.template_name,
          delivery.state
        ]
      end

      def create_delivery!(delivery)
        record = event.event_deliveries.create!(
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

      def spent_routes
        @matched_routes.select(&:single_use?).uniq
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
