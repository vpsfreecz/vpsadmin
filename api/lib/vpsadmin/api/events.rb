require 'json'
require 'time'

module VpsAdmin::API
  module Events
    EVALUATION_TIMEOUT = 0.5
    DELIVERY_LABEL_LIMIT = 255
    PARAMETER_SAMPLE_LIMIT = 30
    FALLBACK_COLLECTION_LIMIT = 100
    REQUEST_EVENT_TYPES = %w[
      request.created
      request.updated
      request.resolved
    ].freeze
    OUTAGE_EVENT_TYPES = %w[
      outage.announced
      outage.updated
    ].freeze
    SYSTEM_REPORT_TEMPLATES = {
      'system.daily_report' => :daily_report,
      'payments.overview' => :payments_overview
    }.freeze
    SYSTEM_REPORT_EVENT_TYPES = SYSTEM_REPORT_TEMPLATES.keys.freeze
    REQUEST_TEMPLATE_CANDIDATES = {
      'request.created' => %i[
        request_action_role_type
        request_action_role
      ],
      'request.updated' => %i[
        request_action_role_type
        request_action_role
      ],
      'request.resolved' => %i[
        request_resolve_role_type_state
        request_action_role_type
        request_resolve_role_state
        request_action_role
      ]
    }.freeze

    Type = Struct.new(
      :name,
      :label,
      :category,
      :severity,
      :parameters,
      :email_template
    )

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
    OutageEntityInfo = Struct.new(:real_name)
    OutageHandlerInfo = Struct.new(:full_name)
    OutageInfo = Struct.new(
      :id,
      :outage_type,
      :state,
      :impact_type,
      :begins_at,
      :finished_at,
      :duration,
      :summary,
      :description,
      :entity_labels,
      :handler_names
    ) do
      def outage_type_label
        ::Outage.outage_type_label(outage_type)
      rescue NameError
        outage_type.to_s
      end

      def impact_type_label
        ::Outage.impact_type_label(impact_type)
      rescue NameError
        impact_type.to_s
      end

      def en_summary
        summary.to_s
      end

      def en_description
        description.to_s
      end

      def outage_entities
        Array(entity_labels).map { |label| OutageEntityInfo.new(label) }
      end

      def outage_handlers
        Array(handler_names).map { |name| OutageHandlerInfo.new(name) }
      end

      def to_hash
        {
          id:,
          type: outage_type,
          begins_at: begins_at&.iso8601,
          duration:,
          impact: impact_type,
          entities: outage_entities.map { |entity| { label: entity.real_name } },
          handlers: outage_handlers.map(&:full_name),
          translations: {
            en: {
              summary: en_summary,
              description: en_description
            }
          }
        }
      end
    end
    OutageUpdateInfo = Struct.new(
      :id,
      :outage,
      :state,
      :impact_type,
      :begins_at,
      :finished_at,
      :duration,
      :summary,
      :description,
      :reporter_name,
      :changes
    ) do
      def outage_type
        outage&.outage_type
      end

      def outage_type_label
        outage&.outage_type_label.to_s
      end

      def impact_type_label
        ::Outage.impact_type_label(impact_type)
      rescue NameError
        impact_type.to_s
      end

      def each_change
        Array(changes).each do |change|
          data = change.respond_to?(:to_h) ? change.to_h : {}
          field = data['field'] || data[:field]
          next if field.blank?

          yield(
            field.to_sym,
            normalize_change_value(field, data['from'] || data[:from]),
            normalize_change_value(field, data['to'] || data[:to])
          )
        end
      end

      def to_hash
        ret = {
          id:,
          changes: {},
          translations: {
            en: {
              summary: summary.to_s,
              description: description.to_s
            }
          }
        }

        each_change do |attr, old, new|
          key = attr == :impact_type ? :type : attr
          ret[:changes][key] = { from: old, to: new }
        end

        ret
      end

      def normalize_change_value(field, value)
        return if value.nil?
        return VpsAdmin::API::Events.parse_time(value) if %w[begins_at finished_at].include?(field.to_s)

        value
      end
    end
    PaymentInfo = Struct.new(
      :id,
      :amount,
      :from_date,
      :to_date,
      :received_amount,
      :received_currency,
      :incoming_payment_id
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
      :next_attempt_at,
      :payload
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
      return action.template_name.to_sym if action&.template_name.present?
      return request_email_template_name_for(event) if REQUEST_EVENT_TYPES.include?(event.event_type)
      return outage_email_template_choice(event).first if OUTAGE_EVENT_TYPES.include?(event.event_type)
      if event.user_id.blank? && SYSTEM_REPORT_EVENT_TYPES.include?(event.event_type)
        return SYSTEM_REPORT_TEMPLATES.fetch(event.event_type)
      end

      type_for(event.event_type)&.email_template&.to_sym
    end

    def email_template_params_for(event)
      case event.event_type
      when 'lifetime.expiration_warning'
        params = event.parameters || {}
        {
          object: params['object'] || params[:object],
          state: params['state'] || params[:state]
        }
      when *REQUEST_EVENT_TYPES
        request_email_template_params(event)
      when *OUTAGE_EVENT_TYPES
        outage_email_template_choice(event).last
      end
    end

    def email_template_options_for(event, delivery)
      opts = {
        user: event.user,
        vars: email_vars_for(event)
      }
      template_params = email_template_params_for(event)
      opts[:params] = template_params if template_params

      if delivery.custom_target_kind?
        opts[:to] = email_target_addresses(event, delivery)
        opts[:include_default_recipients] = false
        opts[:include_template_recipients] = false
      elsif explicit_default_target?(delivery)
        opts[:to] = email_target_addresses(event, delivery)
      end

      opts.merge!(email_template_extra_options_for(event))
      opts
    end

    def email_custom_options_for(event, delivery)
      {
        user: event.user,
        from: MailTemplates.default_from,
        to: email_target_addresses(event, delivery),
        subject: event.subject,
        text_plain: custom_email_body(event, delivery)
      }.merge(custom_email_extra_options_for(event, delivery))
    end

    def custom_email_extra_options_for(event, delivery)
      return {} unless direct_incident_reply_delivery?(event, delivery)

      params = event.parameters || {}
      {
        from: params['from_email'] || params[:from_email],
        in_reply_to: params['in_reply_to_message_id'] || params[:in_reply_to_message_id],
        references: params['references_message_id'] || params[:references_message_id]
      }.compact
    end

    def direct_incident_reply_delivery?(event, delivery)
      event.event_type == 'incident_report.reply' &&
        delivery&.direct_custom_email_delivery?
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
      when 'lifetime.expiration_warning'
        expiration_warning_email_vars(event)
      when 'payment.accepted'
        payment_accepted_email_vars(event)
      when *REQUEST_EVENT_TYPES
        request_email_vars(event)
      when *OUTAGE_EVENT_TYPES
        outage_email_vars(event)
      when 'security_advisory.announced', 'security_advisory.updated'
        security_advisory_email_vars(event)
      when 'vps.incident_report'
        incident_email_vars(event)
      when 'vps.oom_report'
        oom_report_email_vars(event)
      when 'vps.oom_prevention'
        oom_prevention_email_vars(event)
      when 'vps.suspended', 'vps.resumed'
        vps_state_email_vars(event)
      when 'vps.resources_changed'
        vps_resources_email_vars(event)
      when 'vps.dns_resolver_changed'
        vps_dns_resolver_email_vars(event)
      when 'vps.network_disabled', 'vps.network_enabled'
        vps_network_email_vars(event)
      when 'vps.stopped_over_quota'
        vps_stopped_over_quota_email_vars(event)
      when 'vps.dataset_expanded', 'vps.dataset_shrunk'
        vps_dataset_expansion_email_vars(event)
      when 'snapshot.download_ready'
        snapshot_download_email_vars(event)
      when 'dataset.migration_begun', 'dataset.migration_finished'
        dataset_migration_email_vars(event)
      when 'vps.migration_planned', 'vps.migration_begun', 'vps.migration_finished'
        vps_migration_email_vars(event)
      when 'vps.replaced'
        vps_replaced_email_vars(event)
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

    def expiration_warning_email_vars(event)
      params = event.parameters || {}
      object = expiration_warning_object(event)
      object_key = params['object'] || params[:object]
      state = object_state_from_parameters(event)
      expires_in_days = numeric_param(params['expires_in_days'] || params[:expires_in_days])
      expired_days_ago = numeric_param(params['expired_days_ago'] || params[:expired_days_ago])

      ret = {
        base_url: ::SysConfig.get(:webui, :base_url),
        user: event.user,
        object:,
        state:,
        expires_in_days:,
        expired_days_ago:,
        expires_in_a_day: truthy_param(params['expires_in_a_day'] || params[:expires_in_a_day])
      }
      ret[object_key] = object if object_key.present?
      ret
    end

    def payment_accepted_email_vars(event)
      payment = payment_source(event) || payment_from_parameters(event)
      raise ArgumentError, 'payment source is missing' unless payment

      {
        user: event.user,
        account: event.user&.user_account,
        payment:
      }
    end

    def request_email_vars(event)
      request = request_source(event) || request_from_parameters(event)
      raise ArgumentError, 'request source is missing' unless request

      {
        request:,
        r: request,
        webui_url:
      }
    end

    def outage_email_vars(event)
      outage = outage_source(event) || outage_from_parameters(event)
      raise ArgumentError, 'outage is missing' unless outage

      update = outage_update_from_parameters(event, outage)
      params = event.parameters || {}
      role = (params['role'] || params[:role]).to_s
      user = role == 'user' ? event.user : nil

      {
        outage:,
        o: outage,
        update:,
        user:,
        vpses: outage_vpses_for(outage, user),
        direct_vpses: outage_vpses_for(outage, user, direct: true),
        indirect_vpses: outage_vpses_for(outage, user, direct: false),
        exports: outage_exports_for(outage, user),
        security_advisory_cves: outage_security_advisory_cves(outage),
        webui_url:
      }
    end

    def request_email_template_name_for(event)
      candidates = REQUEST_TEMPLATE_CANDIDATES.fetch(event.event_type)
      params = request_email_template_params(event)
      language = request_email_language(event)

      candidates.find do |candidate|
        email_template_available?(candidate, params, language)
      end || candidates.first
    end

    def request_email_template_params(event)
      params = event.parameters || {}
      {
        action: params['action'] || params[:action],
        role: params['role'] || params[:role],
        type: params['request_type'] || params[:request_type],
        state: params['request_state'] || params[:request_state]
      }
    end

    def request_email_language(event)
      params = event.parameters || {}
      return event.user&.language unless (params['role'] || params[:role]).to_s == 'user'

      request = request_source(event) || request_from_parameters(event)
      request&.user_language || event.user&.language
    end

    def outage_email_template_choice(event)
      params = outage_email_template_params(event)
      role = params[:role]
      event_name = params[:event]
      language = role == 'generic' ? ::Language.take : event.user&.language
      choices = [
        [:outage_report_role_event, { role:, event: event_name }],
        [:outage_report_role_event, { role:, event: 'update' }],
        [:outage_report_role, { role: }]
      ]

      choices.find do |name, choice_params|
        email_template_available?(name, choice_params, language)
      end || choices.first
    end

    def outage_email_template_params(event)
      params = event.parameters || {}
      {
        role: params['role'] || params[:role] || 'user',
        event: params['event'] || params[:event] || 'update'
      }
    end

    def email_template_available?(name, params, language)
      resolved_name = ::MailTemplate.resolve_name(name, params)
      template = ::MailTemplate.find_by(name: resolved_name)
      return false unless template
      return true unless language

      template.mail_template_translations.where(language:).exists?
    rescue StandardError
      false
    end

    def email_template_extra_options_for(event)
      return request_email_template_extra_options(event) if REQUEST_EVENT_TYPES.include?(event.event_type)
      return outage_email_template_extra_options(event) if OUTAGE_EVENT_TYPES.include?(event.event_type)
      if event.user_id.blank? && SYSTEM_REPORT_EVENT_TYPES.include?(event.event_type)
        return system_report_email_template_extra_options(event)
      end

      {}
    end

    def system_report_email_template_extra_options(event)
      { language: system_report_language(event) }.compact
    end

    def system_report_language(event)
      params = event.parameters || {}
      language = ::Language.find_by(id: params['language_id'] || params[:language_id])
      language ||= ::Language.find_by(code: params['language_code'] || params[:language_code])
      language || ::Language.take
    end

    def request_email_template_extra_options(event)
      params = event.parameters || {}
      ret = {
        language: request_email_language(event),
        message_id: request_message_id(params, 'mail_id')
      }.compact
      reply_to = request_message_id(params, 'reply_to_mail_id')
      if reply_to
        ret[:in_reply_to] = reply_to
        ret[:references] = reply_to
      end
      ret
    end

    def outage_email_template_extra_options(event)
      params = event.parameters || {}
      role = (params['role'] || params[:role]).to_s
      ret = {
        message_id: params['mail_message_id'] || params[:mail_message_id]
      }.compact
      reply_to = params['reply_to_message_id'] || params[:reply_to_message_id]
      if reply_to
        ret[:in_reply_to] = reply_to
        ret[:references] = reply_to
      end
      ret[:language] = ::Language.take if role == 'generic'
      ret
    end

    def explicit_default_target?(delivery)
      delivery.default_recipient_target_kind? &&
        delivery.target_value.present? &&
        delivery.target_value != 'default'
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

      ObjectStateInfo.new(
        state: params['state'] || params[:state],
        reason: params['reason'] || params[:reason],
        expiration_date: parse_time(params['expiration_date'] || params[:expiration_date]),
        user: user_info_from_parameters(params, 'changed_by')
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

    def expiration_warning_object(event)
      params = event.parameters || {}

      case params['object'] || params[:object]
      when 'user'
        event.user
      when 'vps'
        required_vps(event)
      else
        source = event.source
        return if source.nil?
        return unless source.respond_to?(:user_id)
        return if event.user_id.present? && source.user_id != event.user_id

        source
      end
    end

    def payment_source(event)
      return unless defined?(::UserPayment)

      source = event.source
      return unless source.is_a?(::UserPayment)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def payment_from_parameters(event)
      params = event.parameters || {}
      payment = find_from_parameters(event, ::UserPayment, 'payment_id') if defined?(::UserPayment)
      return payment if payment

      PaymentInfo.new(
        params['payment_id'] || params[:payment_id],
        params['amount'] || params[:amount],
        parse_time(params['from_date'] || params[:from_date]),
        parse_time(params['to_date'] || params[:to_date]),
        params['received_amount'] || params[:received_amount],
        params['received_currency'] || params[:received_currency],
        params['incoming_payment_id'] || params[:incoming_payment_id]
      )
    end

    def request_source(event)
      source = event.source
      return unless defined?(::UserRequest) && source.is_a?(::UserRequest)
      return unless request_visible_to_event_user?(event, source)

      source
    end

    def request_from_parameters(event)
      return unless defined?(::UserRequest)

      request_id = (event.parameters || {})['request_id'] || (event.parameters || {})[:request_id]
      return if request_id.blank?

      request = ::UserRequest.find_by(id: request_id)
      return unless request && request_visible_to_event_user?(event, request)

      request
    end

    def request_visible_to_event_user?(event, request)
      params = event.parameters || {}
      role = (params['role'] || params[:role]).to_s

      if role == 'admin'
        event.user&.role == :admin
      elsif event.user_id.blank?
        recipient = params['recipient_email'] || params[:recipient_email]
        recipient.present? && recipient == request.user_mail
      else
        request.user_id == event.user_id
      end
    end

    def outage_source(event)
      return unless defined?(::Outage)

      source = event.source
      outage = if source.is_a?(::Outage)
                 source
               elsif defined?(::OutageUpdate) && source.is_a?(::OutageUpdate)
                 source.outage
               end
      return unless outage && outage_visible_to_event_user?(event, outage)

      outage
    end

    def outage_from_parameters(event)
      params = event.parameters || {}
      outage_id = params['outage_id'] || params[:outage_id]
      outage = if defined?(::Outage) && outage_id.present?
                 ::Outage.visible_to(event.user).find_by(id: outage_id)
               end
      return outage if outage && outage_visible_to_event_user?(event, outage)

      OutageInfo.new(
        outage_id,
        params['outage_type'] || params[:outage_type],
        params['state'] || params[:state],
        params['impact_type'] || params[:impact_type],
        parse_time(params['begins_at'] || params[:begins_at]),
        parse_time(params['finished_at'] || params[:finished_at]),
        params['duration'] || params[:duration],
        params['outage_summary'] || params[:outage_summary] || params['summary'] || params[:summary],
        params['outage_description'] || params[:outage_description] || params['description'] || params[:description],
        params['entity_labels'] || params[:entity_labels] || [],
        params['handler_names'] || params[:handler_names] || []
      )
    end

    def outage_update_from_parameters(event, outage)
      params = event.parameters || {}

      OutageUpdateInfo.new(
        params['update_id'] || params[:update_id],
        outage,
        params['update_state'] || params[:update_state] || params['state'] || params[:state],
        params['update_impact_type'] || params[:update_impact_type] || params['impact_type'] || params[:impact_type],
        parse_time(params['update_begins_at'] || params[:update_begins_at] || params['begins_at'] || params[:begins_at]),
        parse_time(params['update_finished_at'] || params[:update_finished_at] || params['finished_at'] || params[:finished_at]),
        params['update_duration'] || params[:update_duration] || params['duration'] || params[:duration],
        params['summary'] || params[:summary],
        params['description'] || params[:description],
        params['reported_by_name'] || params[:reported_by_name],
        params['changes'] || params[:changes] || []
      )
    end

    def outage_visible_to_event_user?(event, outage)
      return true if event.user_id.blank?

      params = event.parameters || {}
      role = (params['role'] || params[:role]).to_s
      case role
      when 'user'
        outage.outage_users.where(user_id: event.user_id).exists?
      when 'generic'
        event.user&.role == :admin
      else
        false
      end
    end

    def outage_vpses_for(outage, user, direct: nil)
      return unless user
      return [] unless outage.respond_to?(:outage_vpses)

      scope = outage.outage_vpses.where(user:)
      scope = scope.where(direct:) unless direct.nil?
      scope
    end

    def outage_exports_for(outage, user)
      return unless user
      return [] unless outage.respond_to?(:outage_exports)

      outage.outage_exports.where(user:)
    end

    def outage_security_advisory_cves(outage)
      return [] unless outage.respond_to?(:outage_security_advisories)

      outage.outage_security_advisories
            .includes(security_advisory: :security_advisory_cves)
            .flat_map do |link|
        advisory = link.security_advisory

        advisory.security_advisory_cves.order(:cve_id).map do |cve|
          {
            advisory_id: advisory.id,
            advisory_name: advisory.name,
            cve_id: cve.cve_id,
            cve_url: cve.url
          }
        end
      end.uniq { |row| [row[:advisory_id], row[:cve_id]] }
    end

    def default_email_target_for(event)
      return unless REQUEST_EVENT_TYPES.include?(event.event_type)

      params = event.parameters || {}
      return unless (params['role'] || params[:role]).to_s == 'user'

      params['recipient_email'] || params[:recipient_email]
    end

    def custom_email_target_for(event)
      return unless event.event_type == 'incident_report.reply'

      params = event.parameters || {}
      recipients = Array(params['recipient_emails'] || params[:recipient_emails])
                   .map(&:to_s)
                   .reject(&:blank?)
      return if recipients.empty?

      recipients.join(',')
    end

    def system_template_email?(event)
      return true if SYSTEM_REPORT_EVENT_TYPES.include?(event.event_type)
      return false unless OUTAGE_EVENT_TYPES.include?(event.event_type)

      params = event.parameters || {}
      (params['role'] || params[:role]).to_s == 'generic'
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

    def vps_state_email_vars(event)
      {
        vps: required_vps(event),
        state: object_state_source(event) || object_state_from_parameters(event)
      }
    end

    def vps_resources_email_vars(event)
      params = event.parameters || {}

      {
        vps: required_vps(event),
        admin: user_info_from_parameters(params, 'admin'),
        reason: params['reason'] || params[:reason]
      }
    end

    def vps_dns_resolver_email_vars(event)
      {
        vps: required_vps(event),
        old_dns_resolver: dns_resolver_from_parameters(event, 'old'),
        new_dns_resolver: dns_resolver_from_parameters(event, 'new')
      }
    end

    def vps_network_email_vars(event)
      params = event.parameters || {}

      {
        user: event.user,
        vps: required_vps(event),
        reason: params['reason'] || params[:reason] || ''
      }
    end

    def vps_stopped_over_quota_email_vars(event)
      vps_dataset_expansion_email_vars(event)
    end

    def vps_dataset_expansion_email_vars(event)
      expansion = dataset_expansion_source(event) || dataset_expansion_from_parameters(event)
      dataset = expansion.is_a?(::DatasetExpansion) ? expansion.dataset : dataset_from_parameters(event)

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        vps: required_vps(event),
        expansion:,
        dataset:
      }
    end

    def snapshot_download_email_vars(event)
      download = snapshot_download_source(event)
      return { base_url: ::SysConfig.get(:webui, :base_url), dl: download } if download

      params = event.parameters || {}
      dataset = dataset_from_parameters(event)
      snapshot = SnapshotInfo.new(
        id: params['snapshot_id'] || params[:snapshot_id],
        name: params['snapshot_name'] || params[:snapshot_name],
        dataset:
      )
      download = SnapshotDownloadInfo.new(
        id: params['download_id'] || params[:download_id],
        file_name: params['file_name'] || params[:file_name],
        expiration_date: parse_time(params['expiration_date'] || params[:expiration_date]),
        user: event.user,
        snapshot:
      )

      {
        base_url: ::SysConfig.get(:webui, :base_url),
        dl: download
      }
    end

    def dataset_migration_email_vars(event)
      params = event.parameters || {}
      dataset = dataset_source(event) || dataset_from_parameters(event)

      {
        dataset:,
        src_pool: pool_info_from_parameters(params, 'src'),
        dst_pool: pool_info_from_parameters(params, 'dst'),
        exports: Array.new(bounded_collection_count(params['export_count'] || params[:export_count])),
        export_mounts: [],
        vpses: vps_infos_from_parameters(event),
        restart_vps: truthy_param(params['restart_vps'] || params[:restart_vps]),
        maintenance_window: truthy_param(params['maintenance_window'] || params[:maintenance_window]),
        maintenance_windows: [],
        custom_window: truthy_param(params['custom_window'] || params[:custom_window]),
        finish_weekday: params['finish_weekday'] || params[:finish_weekday],
        finish_minutes: params['finish_minutes'] || params[:finish_minutes],
        reason: params['reason'] || params[:reason]
      }
    end

    def vps_migration_email_vars(event)
      params = event.parameters || {}

      {
        m: vps_migration_source(event) || VpsMigrationInfo.new(
          id: params['migration_id'] || params[:migration_id],
          maintenance_window: truthy_param(params['maintenance_window'] || params[:maintenance_window])
        ),
        vps: required_vps(event),
        src_node: node_info_from_parameters(params, 'src'),
        dst_node: node_info_from_parameters(params, 'dst'),
        maintenance_window: truthy_param(params['maintenance_window'] || params[:maintenance_window]),
        maintenance_windows: [],
        custom_window: truthy_param(params['custom_window'] || params[:custom_window]),
        finish_weekday: params['finish_weekday'] || params[:finish_weekday],
        finish_minutes: params['finish_minutes'] || params[:finish_minutes],
        reason: params['reason'] || params[:reason]
      }
    end

    def vps_replaced_email_vars(event)
      params = event.parameters || {}
      new_vps = secondary_vps_source(event) ||
                find_vps_from_parameters(event, 'new_vps_id') ||
                vps_info_from_parameters(event, 'new')

      {
        original_vps: required_vps(event),
        new_vps:,
        reason: params['reason'] || params[:reason]
      }
    end

    def security_advisory_email_vars(event)
      advisory = security_advisory_source(event) ||
                 security_advisory_from_parameters(event)
      raise ArgumentError, 'security advisory is missing' unless advisory

      update = security_advisory_update_source(event, advisory) ||
               security_advisory_update_from_parameters(event, advisory)
      if event.event_type == 'security_advisory.updated' && update.nil?
        raise ArgumentError, 'security advisory update is missing'
      end

      {
        advisory:,
        a: advisory,
        update:,
        user: event.user,
        vpses: security_advisory_vpses_for(advisory, event.user),
        webui_url: webui_url
      }
    end

    def required_vps(event)
      vps = event.vps
      raise ArgumentError, "#{event.event_type} VPS is missing" unless vps

      if event.user_id.present? && vps.user_id != event.user_id
        raise ArgumentError, "#{event.event_type} VPS does not belong to event user"
      end

      vps
    end

    def dns_resolver_from_parameters(event, prefix)
      params = event.parameters || {}

      DnsResolverInfo.new(
        id: params["#{prefix}_dns_resolver_id"] || params[:"#{prefix}_dns_resolver_id"],
        label: params["#{prefix}_dns_resolver_label"] || params[:"#{prefix}_dns_resolver_label"],
        addrs: params["#{prefix}_dns_resolver_addrs"] || params[:"#{prefix}_dns_resolver_addrs"] || ''
      )
    end

    def user_info_from_parameters(params, prefix)
      login = params["#{prefix}_login"] || params[:"#{prefix}_login"]
      full_name = params["#{prefix}_name"] || params[:"#{prefix}_name"] || login
      return if full_name.blank?

      UserInfo.new(
        id: params["#{prefix}_id"] || params[:"#{prefix}_id"],
        login: login || full_name,
        full_name:
      )
    end

    def dataset_expansion_source(event)
      source = event.source
      return unless source.is_a?(::DatasetExpansion)
      return if event.vps_id.present? && source.vps_id != event.vps_id
      return if event.user_id.present? && source.vps.user_id != event.user_id

      source
    end

    def snapshot_download_source(event)
      source = event.source
      return unless source.is_a?(::SnapshotDownload)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def dataset_source(event)
      source = event.source
      return unless source.is_a?(::Dataset)
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def vps_migration_source(event)
      source = event.source
      return unless source.is_a?(::VpsMigration)
      return if event.user_id.present? && source.vps.user_id != event.user_id

      source
    end

    def secondary_vps_source(event)
      source = event.source
      return unless source.is_a?(::Vps)
      return if event.vps_id.present? && source.id == event.vps_id
      return if event.user_id.present? && source.user_id != event.user_id

      source
    end

    def security_advisory_source(event)
      case event.source
      when ::SecurityAdvisory
        event.source
      when ::SecurityAdvisoryUpdate
        event.source.security_advisory
      end
    end

    def security_advisory_update_source(event, advisory)
      source = event.source
      return unless source.is_a?(::SecurityAdvisoryUpdate)
      return unless source.security_advisory_id == advisory.id

      source
    end

    def security_advisory_from_parameters(event)
      params = event.parameters || {}
      advisory_id = params['advisory_id'] || params[:advisory_id]
      return if advisory_id.blank?

      ::SecurityAdvisory.visible_to(event.user).find_by(id: advisory_id)
    end

    def security_advisory_update_from_parameters(event, advisory)
      params = event.parameters || {}
      update_id = params['update_id'] || params[:update_id]
      return if update_id.blank?

      advisory.security_advisory_updates.find_by(id: update_id)
    end

    def security_advisory_vpses_for(advisory, user)
      scope = advisory.security_advisory_vpses.includes(:vps, :node).order(:vps_id)
      return scope.none unless user

      scope.where(user:)
    end

    def dataset_expansion_from_parameters(event)
      params = event.parameters || {}

      DatasetExpansionInfo.new(
        id: params['expansion_id'] || params[:expansion_id],
        original_refquota: (params['original_refquota'] || params[:original_refquota]).to_i,
        added_space: (params['added_space'] || params[:added_space]).to_i,
        expansion_count: (params['expansion_count'] || params[:expansion_count]).to_i,
        over_refquota_seconds: (params['over_refquota_seconds'] || params[:over_refquota_seconds]).to_i,
        max_over_refquota_seconds: (params['max_over_refquota_seconds'] || params[:max_over_refquota_seconds]).to_i,
        enable_shrink: params['enable_shrink'] || params[:enable_shrink]
      )
    end

    def dataset_from_parameters(event)
      params = event.parameters || {}

      DatasetInfo.new(
        id: params['dataset_id'] || params[:dataset_id],
        full_name: params['dataset_full_name'] || params[:dataset_full_name],
        refquota: (params['dataset_refquota'] || params[:dataset_refquota]).to_i,
        referenced: (params['dataset_referenced'] || params[:dataset_referenced]).to_i,
        user: event.user || user_info_from_parameters(params, 'user')
      )
    end

    def node_info_from_parameters(params, prefix)
      NodeInfo.new(
        id: params["#{prefix}_node_id"] || params[:"#{prefix}_node_id"],
        domain_name: params["#{prefix}_node_domain_name"] || params[:"#{prefix}_node_domain_name"]
      )
    end

    def pool_info_from_parameters(params, prefix)
      PoolInfo.new(
        id: params["#{prefix}_pool_id"] || params[:"#{prefix}_pool_id"],
        filesystem: params["#{prefix}_pool_filesystem"] || params[:"#{prefix}_pool_filesystem"]
      )
    end

    def vps_infos_from_parameters(event)
      params = event.parameters || {}

      Array(params['affected_vpses'] || params[:affected_vpses]).map do |item|
        data = item.respond_to?(:to_h) ? item.to_h : {}
        VpsInfo.new(
          id: data['id'] || data[:id],
          hostname: data['hostname'] || data[:hostname],
          user: event.user
        )
      end
    end

    def vps_info_from_parameters(event, prefix)
      params = event.parameters || {}
      hostname = params["#{prefix}_vps_hostname"] || params[:"#{prefix}_vps_hostname"]
      return if hostname.blank?

      VpsInfo.new(
        id: params["#{prefix}_vps_id"] || params[:"#{prefix}_vps_id"],
        hostname:,
        user: event.user
      )
    end

    def find_vps_from_parameters(event, key)
      value = (event.parameters || {})[key] || (event.parameters || {})[key.to_sym]
      return if value.blank?

      scope = ::Vps.including_deleted
      scope = scope.where(user_id: event.user_id) if event.user_id.present?
      scope.find_by(id: value)
    end

    def truthy_param(value)
      value == true || value.to_s == 'true' || value.to_s == '1'
    end

    def numeric_param(value)
      return if value.blank?

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def bounded_collection_count(value)
      count = value.to_i
      return 0 if count < 0

      [count, FALLBACK_COLLECTION_LIMIT].min
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

    def request_message_id(params, key)
      mail_id = params[key] || params[key.to_sym]
      request_id = params['request_id'] || params[:request_id]
      return if request_id.blank? || mail_id.blank?

      format(::SysConfig.get(:plugin_requests, :message_id), id: request_id, mail_id:)
    rescue StandardError
      nil
    end

    def custom_email_body(event, delivery)
      if direct_incident_reply_delivery?(event, delivery)
        params = event.parameters || {}
        text = params['text'] || params[:text]
        return text if text.present?
      end

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
              release: true, email_vars: nil)
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
      event.runtime_email_vars = email_vars if email_vars
      VpsAdmin::API::Notifications::Release.release!(event.event_deliveries.where(state: 'prepared')) if route && release

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
          deliveries = direct_deliveries
          deliveries = [skipped_delivery(nil, nil, nil, 'no route matched the event')] if deliveries.empty?
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
              template_name: VpsAdmin::API::Events.email_template_name_for(event),
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
              template_name: VpsAdmin::API::Events.email_template_name_for(event),
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
            template_name: VpsAdmin::API::Events.email_template_name_for(event),
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

      def build_delivery(route, receiver, receiver_action, target_value:, target_label:, template_name: nil,
                         target_kind: nil, state: 'prepared', next_attempt_at: nil, payload: nil)
        DeliveryPlan.new(
          action: receiver_action&.action || 'email',
          target_kind: target_kind || receiver_action&.target_kind || 'default_recipient',
          target_value:,
          target_label: delivery_label(target_label),
          template_name: template_name || delivery_template_name(receiver_action),
          event_route: route,
          notification_receiver: receiver,
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
        return unless receiver_action
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
        record = event.event_deliveries.create!(
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
          next_attempt_at: delivery.next_attempt_at,
          payload: delivery.payload
        )

        record.association(:event).target = event if event.runtime_email_vars

        if record.email_action? && record.prepared_state?
          VpsAdmin::API::Notifications.render_email_delivery!(record)
        elsif record.webhook_action? && record.prepared_state? && record.payload.blank?
          record.update!(payload: JSON.dump(VpsAdmin::API::Notifications.webhook_payload_for(record)))
        end

        record
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
      'system.daily_report',
      label: 'Daily report',
      category: 'system',
      severity: :info,
      parameters: {
        language_id: 'Mail language ID',
        language_code: 'Mail language code',
        period_start: 'Report period start',
        period_end: 'Report period end',
        period_seconds: 'Report period in seconds'
      }
    )

    register(
      'payment.accepted',
      label: 'Payment accepted',
      category: 'payments',
      severity: :info,
      email_template: :payment_accepted,
      parameters: {
        payment_id: 'Payment ID',
        amount: 'Accounted amount',
        received_amount: 'Received amount',
        received_currency: 'Received currency',
        from_date: 'Paid from date',
        to_date: 'Paid until date',
        incoming_payment_id: 'Incoming payment ID',
        incoming_transaction_id: 'Incoming bank transaction ID',
        accounted_by_id: 'Accounting admin user ID',
        accounted_by_login: 'Accounting admin login'
      }
    )

    register(
      'payments.overview',
      label: 'Payments overview',
      category: 'payments',
      severity: :info,
      parameters: {
        language_id: 'Mail language ID',
        language_code: 'Mail language code',
        period_start: 'Report period start',
        period_end: 'Report period end',
        period_seconds: 'Report period in seconds',
        incoming_payment_count: 'Incoming payment count',
        accepted_payment_count: 'Accepted payment count'
      }
    )

    register(
      'outage.announced',
      label: 'Outage announced',
      category: 'outages',
      severity: :warning,
      parameters: {
        role: 'Recipient role',
        event: 'Outage mail event',
        outage_id: 'Outage ID',
        update_id: 'Outage update ID',
        outage_type: 'Outage type',
        state: 'Outage state',
        impact_type: 'Impact type',
        begins_at: 'Beginning time',
        finished_at: 'Finish time',
        duration: 'Expected duration in minutes',
        summary: 'Update summary',
        description: 'Update description',
        outage_summary: 'Outage summary',
        outage_description: 'Outage description',
        entity_labels: 'Affected entity labels',
        handler_names: 'Handler names',
        affected_user_id: 'Affected user ID',
        affected_user_login: 'Affected user login',
        affected_vps_count: 'Affected VPS count',
        direct_vps_count: 'Directly affected VPS count',
        indirect_vps_count: 'Indirectly affected VPS count',
        affected_export_count: 'Affected export count',
        cves: 'Related CVE identifiers',
        reported_by_id: 'Reporting admin user ID',
        reported_by_login: 'Reporting admin login',
        reported_by_name: 'Reporting admin name'
      }
    )

    register(
      'outage.updated',
      label: 'Outage updated',
      category: 'outages',
      severity: :warning,
      parameters: {
        role: 'Recipient role',
        event: 'Outage mail event',
        outage_id: 'Outage ID',
        update_id: 'Outage update ID',
        outage_type: 'Outage type',
        state: 'Outage state',
        impact_type: 'Impact type',
        begins_at: 'Beginning time',
        finished_at: 'Finish time',
        duration: 'Expected duration in minutes',
        summary: 'Update summary',
        description: 'Update description',
        outage_summary: 'Outage summary',
        outage_description: 'Outage description',
        changes: 'Changed outage fields',
        affected_user_id: 'Affected user ID',
        affected_user_login: 'Affected user login',
        affected_vps_count: 'Affected VPS count',
        direct_vps_count: 'Directly affected VPS count',
        indirect_vps_count: 'Indirectly affected VPS count',
        affected_export_count: 'Affected export count',
        cves: 'Related CVE identifiers',
        reported_by_id: 'Reporting admin user ID',
        reported_by_login: 'Reporting admin login',
        reported_by_name: 'Reporting admin name'
      }
    )

    register(
      'request.created',
      label: 'Request created',
      category: 'requests',
      severity: :info,
      parameters: {
        action: 'Request action',
        role: 'Recipient role',
        request_id: 'Request ID',
        request_type: 'Request type',
        request_state: 'Request state',
        request_label: 'Request label',
        user_id: 'Request owner user ID',
        user_login: 'Request owner login',
        recipient_email: 'Recipient e-mail',
        mail_id: 'Request mail thread ID'
      }
    )

    register(
      'request.updated',
      label: 'Request updated',
      category: 'requests',
      severity: :info,
      parameters: {
        action: 'Request action',
        role: 'Recipient role',
        request_id: 'Request ID',
        request_type: 'Request type',
        request_state: 'Request state',
        request_label: 'Request label',
        user_id: 'Request owner user ID',
        user_login: 'Request owner login',
        recipient_email: 'Recipient e-mail',
        mail_id: 'Request mail thread ID',
        reply_to_mail_id: 'Previous request mail thread ID'
      }
    )

    register(
      'request.resolved',
      label: 'Request resolved',
      category: 'requests',
      severity: :info,
      parameters: {
        action: 'Request action',
        role: 'Recipient role',
        request_id: 'Request ID',
        request_type: 'Request type',
        request_state: 'Request state',
        request_label: 'Request label',
        user_id: 'Request owner user ID',
        user_login: 'Request owner login',
        recipient_email: 'Recipient e-mail',
        admin_id: 'Resolving admin user ID',
        admin_login: 'Resolving admin login',
        reason: 'Resolution reason',
        mail_id: 'Request mail thread ID',
        reply_to_mail_id: 'Previous request mail thread ID'
      }
    )

    register(
      'lifetime.expiration_warning',
      label: 'Expiration warning',
      category: 'account',
      severity: :warning,
      email_template: :expiration_warning,
      parameters: {
        object: 'Expiring object type',
        object_id: 'Expiring object ID',
        object_label: 'Expiring object label',
        state: 'Object lifecycle state',
        expiration_date: 'Expiration date',
        remind_after_date: 'Reminder silence date',
        expires_in_days: 'Days until expiration',
        expired_days_ago: 'Days since expiration',
        expires_in_a_day: 'Whether expiration is within a day'
      }
    )

    register(
      'security_advisory.announced',
      label: 'Security advisory announced',
      category: 'security',
      severity: :warning,
      email_template: :security_advisory_user_announce,
      parameters: {
        advisory_id: 'Security advisory ID',
        advisory_name: 'Security advisory name',
        cves: 'CVE identifiers',
        state: 'Security advisory state',
        published_at: 'Publication time',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample'
      }
    )

    register(
      'security_advisory.updated',
      label: 'Security advisory updated',
      category: 'security',
      severity: :warning,
      email_template: :security_advisory_user_update,
      parameters: {
        advisory_id: 'Security advisory ID',
        advisory_name: 'Security advisory name',
        update_id: 'Security advisory update ID',
        update_summary: 'Update summary',
        cves: 'CVE identifiers',
        state: 'Security advisory state',
        published_at: 'Publication time',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample'
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
      'incident_report.reply',
      label: 'Incident report reply',
      category: 'incidents',
      severity: :info,
      parameters: {
        from_email: 'Reply sender e-mail',
        recipient_emails: 'Reply recipient e-mail addresses',
        in_reply_to_message_id: 'Original Message-ID',
        references_message_id: 'References Message-ID',
        incident_count: 'Created incident report count',
        user_count: 'Affected user count',
        vps_count: 'Affected VPS count',
        incident_ids: 'Created incident report ID sample',
        text: 'Reply text'
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

    register(
      'vps.suspended',
      label: 'VPS suspended',
      category: 'vps',
      severity: :warning,
      email_template: :vps_suspend,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date',
        changed_by_id: 'User ID that changed the state',
        changed_by_name: 'User name that changed the state'
      }
    )

    register(
      'vps.resumed',
      label: 'VPS resumed',
      category: 'vps',
      severity: :info,
      email_template: :vps_resume,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        state: 'Lifecycle state',
        reason: 'Lifecycle reason',
        expiration_date: 'Expiration date',
        changed_by_id: 'User ID that changed the state',
        changed_by_name: 'User name that changed the state'
      }
    )

    register(
      'vps.resources_changed',
      label: 'VPS resources changed',
      category: 'vps',
      severity: :info,
      email_template: :vps_resources_change,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        cpu: 'CPU cores',
        cpu_limit: 'CPU limit',
        memory: 'Memory in MiB',
        swap: 'Swap in MiB',
        reason: 'Change reason',
        admin_id: 'Admin user ID',
        admin_name: 'Admin name'
      }
    )

    register(
      'vps.dns_resolver_changed',
      label: 'VPS DNS resolver changed',
      category: 'vps',
      severity: :info,
      email_template: :vps_dns_resolver_change,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        old_dns_resolver_id: 'Previous DNS resolver ID',
        old_dns_resolver_label: 'Previous DNS resolver label',
        old_dns_resolver_addrs: 'Previous DNS resolver addresses',
        new_dns_resolver_id: 'New DNS resolver ID',
        new_dns_resolver_label: 'New DNS resolver label',
        new_dns_resolver_addrs: 'New DNS resolver addresses'
      }
    )

    register(
      'vps.network_disabled',
      label: 'VPS network disabled',
      category: 'vps',
      severity: :warning,
      email_template: :vps_network_disabled,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        reason: 'Disable reason'
      }
    )

    register(
      'vps.network_enabled',
      label: 'VPS network enabled',
      category: 'vps',
      severity: :info,
      email_template: :vps_network_enabled,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        reason: 'Enable reason'
      }
    )

    register(
      'vps.stopped_over_quota',
      label: 'VPS stopped over quota',
      category: 'vps',
      severity: :warning,
      email_template: :vps_stopped_over_quota,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        dataset_refquota: 'Dataset refquota',
        dataset_referenced: 'Dataset referenced space',
        expansion_id: 'Dataset expansion ID',
        original_refquota: 'Original refquota',
        added_space: 'Added space',
        expansion_count: 'Expansion count',
        over_refquota_seconds: 'Time over quota in seconds',
        max_over_refquota_seconds: 'Maximum time over quota in seconds',
        enable_shrink: 'Whether automatic shrink is enabled'
      }
    )

    register(
      'vps.dataset_expanded',
      label: 'VPS dataset expanded',
      category: 'vps',
      severity: :info,
      email_template: :vps_dataset_expanded,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        dataset_refquota: 'Dataset refquota',
        dataset_referenced: 'Dataset referenced space',
        expansion_id: 'Dataset expansion ID',
        original_refquota: 'Original refquota',
        added_space: 'Added space',
        expansion_count: 'Expansion count'
      }
    )

    register(
      'vps.dataset_shrunk',
      label: 'VPS dataset shrunk',
      category: 'vps',
      severity: :info,
      email_template: :vps_dataset_shrunk,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        dataset_refquota: 'Dataset refquota',
        dataset_referenced: 'Dataset referenced space',
        expansion_id: 'Dataset expansion ID',
        original_refquota: 'Original refquota',
        added_space: 'Added space',
        expansion_count: 'Expansion count'
      }
    )

    register(
      'snapshot.download_ready',
      label: 'Snapshot download ready',
      category: 'storage',
      severity: :info,
      email_template: :snapshot_download_ready,
      parameters: {
        download_id: 'Snapshot download ID',
        snapshot_id: 'Snapshot ID',
        snapshot_name: 'Snapshot name',
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        file_name: 'Download file name',
        format: 'Download format',
        expiration_date: 'Download expiration date'
      }
    )

    register(
      'dataset.migration_begun',
      label: 'Dataset migration begun',
      category: 'storage',
      severity: :warning,
      email_template: :dataset_migration_begun,
      parameters: {
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        user_id: 'Dataset owner user ID',
        user_login: 'Dataset owner login',
        user_name: 'Dataset owner name',
        src_pool_id: 'Source pool ID',
        src_pool_filesystem: 'Source pool filesystem',
        dst_pool_id: 'Destination pool ID',
        dst_pool_filesystem: 'Destination pool filesystem',
        export_count: 'Export count',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample',
        restart_vps: 'Whether affected VPSes are restarted',
        maintenance_window: 'Whether a maintenance window is used',
        custom_window: 'Whether a custom maintenance window is used',
        finish_weekday: 'Maintenance window weekday',
        finish_minutes: 'Maintenance window minute',
        reason: 'Migration reason'
      }
    )

    register(
      'dataset.migration_finished',
      label: 'Dataset migration finished',
      category: 'storage',
      severity: :info,
      email_template: :dataset_migration_finished,
      parameters: {
        dataset_id: 'Dataset ID',
        dataset_full_name: 'Dataset name',
        user_id: 'Dataset owner user ID',
        user_login: 'Dataset owner login',
        user_name: 'Dataset owner name',
        src_pool_id: 'Source pool ID',
        src_pool_filesystem: 'Source pool filesystem',
        dst_pool_id: 'Destination pool ID',
        dst_pool_filesystem: 'Destination pool filesystem',
        export_count: 'Export count',
        affected_vps_count: 'Affected VPS count',
        affected_vpses: 'Affected VPS sample',
        restart_vps: 'Whether affected VPSes are restarted',
        maintenance_window: 'Whether a maintenance window is used',
        custom_window: 'Whether a custom maintenance window is used',
        finish_weekday: 'Maintenance window weekday',
        finish_minutes: 'Maintenance window minute',
        reason: 'Migration reason'
      }
    )

    register(
      'vps.migration_planned',
      label: 'VPS migration planned',
      category: 'vps',
      severity: :warning,
      email_template: :vps_migration_planned,
      parameters: {
        migration_id: 'Migration ID',
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        src_node_id: 'Source node ID',
        src_node_domain_name: 'Source node domain name',
        dst_node_id: 'Destination node ID',
        dst_node_domain_name: 'Destination node domain name',
        maintenance_window: 'Whether a maintenance window is used'
      }
    )

    register(
      'vps.migration_begun',
      label: 'VPS migration begun',
      category: 'vps',
      severity: :warning,
      email_template: :vps_migration_begun,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        src_node_id: 'Source node ID',
        src_node_domain_name: 'Source node domain name',
        dst_node_id: 'Destination node ID',
        dst_node_domain_name: 'Destination node domain name',
        maintenance_window: 'Whether a maintenance window is used',
        custom_window: 'Whether a custom maintenance window is used',
        finish_weekday: 'Maintenance window weekday',
        finish_minutes: 'Maintenance window minute',
        reason: 'Migration reason'
      }
    )

    register(
      'vps.migration_finished',
      label: 'VPS migration finished',
      category: 'vps',
      severity: :info,
      email_template: :vps_migration_finished,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        src_node_id: 'Source node ID',
        src_node_domain_name: 'Source node domain name',
        dst_node_id: 'Destination node ID',
        dst_node_domain_name: 'Destination node domain name',
        maintenance_window: 'Whether a maintenance window is used',
        custom_window: 'Whether a custom maintenance window is used',
        finish_weekday: 'Maintenance window weekday',
        finish_minutes: 'Maintenance window minute',
        reason: 'Migration reason'
      }
    )

    register(
      'vps.replaced',
      label: 'VPS replaced',
      category: 'vps',
      severity: :warning,
      email_template: :vps_replaced,
      parameters: {
        vps_id: 'VPS ID',
        vps_hostname: 'VPS hostname',
        original_vps_id: 'Original VPS ID',
        original_vps_hostname: 'Original VPS hostname',
        new_vps_id: 'New VPS ID',
        new_vps_hostname: 'New VPS hostname',
        reason: 'Replacement reason'
      }
    )
  end
end
