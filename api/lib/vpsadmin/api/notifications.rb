require 'bunny'
require 'digest'
require 'ipaddr'
require 'json'
require 'mail'
require 'net/http'
require 'openssl'
require 'resolv'
require 'securerandom'
require 'time'
require 'uri'
require 'yaml'

module VpsAdmin::API
  module Notifications
    class SmsCallbackAuthenticationError < StandardError; end
    class SmsCallbackConflictError < StandardError; end
    class EmailVerificationDeliveryError < StandardError; end

    module Actions
      class Definition
        attr_reader :name, :target_kinds

        def initialize(name)
          @name = name.to_s
          @target_kinds = {}
        end

        def label(value = nil)
          @label = value if value
          @label
        end

        def target_kind(name, label:)
          @target_kinds[name.to_s] = label
        end

        def validate_receiver_action(&block)
          @validate_receiver_action = block if block
          @validate_receiver_action
        end

        def display_target(&block)
          @display_target = block if block
          @display_target
        end

        def receiver_action_available(&block)
          @receiver_action_available = block if block
          @receiver_action_available
        end

        def available(&block)
          @available = block if block
          @available
        end

        def available?
          return true unless @available

          @available.call
        end

        def plan_delivery(&block)
          @plan_delivery = block if block
          @plan_delivery
        end

        def prepare_delivery(&block)
          @prepare_delivery = block if block
          @prepare_delivery
        end

        def deliver(&block)
          @deliver = block if block
          @deliver
        end

        def validate_receiver_action!(action)
          action.instance_exec(&@validate_receiver_action) if @validate_receiver_action
        end

        def display_target_for(action)
          return action.instance_exec(&@display_target) if @display_target

          action.target_value.presence || action.target_kind.tr('_', ' ')
        end

        def receiver_action_available?(action)
          return false unless available?
          return false unless action && action.action == name
          return false if action.respond_to?(:target_enabled) && !action.target_enabled
          return false if action.respond_to?(:enabled?) && !action.enabled?
          return false unless action.delivery_method_enabled?
          return action.instance_exec(&@receiver_action_available) if @receiver_action_available

          true
        end

        def plan_delivery_for(router, route, receiver, receiver_action)
          router.instance_exec(route, receiver, receiver_action, &@plan_delivery)
        end

        def prepare_delivery_for(router, delivery)
          router.instance_exec(delivery, &@prepare_delivery) if @prepare_delivery
        end

        def deliver_with(dispatcher, delivery)
          dispatcher.instance_exec(delivery, &@deliver)
        end
      end

      @definitions = {}

      module_function

      def define(name, &)
        definition = Definition.new(name)
        definition.instance_exec(&)
        @definitions[definition.name] = definition
      end

      def fetch(name)
        @definitions.fetch(name.to_s)
      end

      def known?(name)
        @definitions.has_key?(name.to_s)
      end

      def names
        @definitions.keys
      end

      def labels
        @definitions.transform_values(&:label)
      end

      def available?(name)
        fetch(name).available?
      rescue KeyError
        false
      end

      def available_names
        @definitions.select { |_, definition| definition.available? }.keys
      end

      def available_labels
        @definitions
          .select { |_, definition| definition.available? }
          .transform_values(&:label)
      end

      def target_kind_labels
        @definitions.values.each_with_object({}) do |definition, ret|
          ret.merge!(definition.target_kinds)
        end
      end
    end

    EXCHANGE_NAME = 'vpsadmin.notifications'.freeze
    QUEUES = {
      'email' => 'vpsadmin.notifications.email',
      'telegram' => 'vpsadmin.notifications.telegram',
      'webhook' => 'vpsadmin.notifications.webhook',
      'sms' => 'vpsadmin.notifications.sms'
    }.freeze
    ROUTING_KEYS = {
      'email' => 'delivery.email',
      'telegram' => 'delivery.telegram',
      'webhook' => 'delivery.webhook',
      'sms' => 'delivery.sms'
    }.freeze
    DEFAULT_LIMIT = 100
    DEFAULT_EMAIL_CONCURRENCY = 2
    DEFAULT_TELEGRAM_CONCURRENCY = 2
    DEFAULT_WEBHOOK_CONCURRENCY = 4
    DEFAULT_SMS_CONCURRENCY = 1
    DEFAULT_EMAIL_WORKER_DELAY = 1.0
    DEFAULT_EMAIL_DOMAIN_MIN_DELIVERY_INTERVAL = 1.0
    EMAIL_DUE_SCAN_MULTIPLIER = 4
    MAX_ATTEMPTS = 5
    CLAIM_TIMEOUT = 5 * 60
    RESPONSE_BODY_LIMIT = 8192
    RESPONSE_HEADERS_LIMIT = 8192
    RESPONSE_HEADER_NAME_LIMIT = 100
    RESPONSE_HEADER_VALUE_LIMIT = 1024
    RESPONSE_HEADER_VALUE_COUNT_LIMIT = 10
    RESPONSE_HEADERS_TRUNCATED = {
      'x-vpsadmin-truncated' => ['response headers truncated']
    }.freeze
    TELEGRAM_HTML_PARSE_MODE = 'HTML'.freeze
    TELEGRAM_LINK_PREVIEW_OPTIONS = { is_disabled: true }.freeze
    TELEGRAM_TEXT_LIMIT = 4096
    SMS_TEXT_LIMIT = 459
    SMS_CALLBACK_PATH = '/internal/notifications/sms/callback'.freeze
    SMS_CALLBACK_MAX_BODY_SIZE = 16 * 1024
    SMS_CALLBACK_SIGNATURE_VERSION = 'v1'.freeze
    SMS_CALLBACK_SIGNATURE_TOLERANCE = 20 * 60
    SMS_VERIFICATION_CLIENT_ID_PREFIX = 'verification-action-'.freeze
    DEFAULT_POLL_INTERVAL = 5
    PRIVATE_ADDRESS_RANGES = [
      '0.0.0.0/8',
      '10.0.0.0/8',
      '100.64.0.0/10',
      '127.0.0.0/8',
      '169.254.0.0/16',
      '172.16.0.0/12',
      '192.0.0.0/24',
      '192.0.2.0/24',
      '192.168.0.0/16',
      '198.18.0.0/15',
      '198.51.100.0/24',
      '203.0.113.0/24',
      '224.0.0.0/4',
      '240.0.0.0/4',
      '::/128',
      '::1/128',
      '::ffff:0:0/96',
      '2001:db8::/32',
      'fc00::/7',
      'fe80::/10',
      'ff00::/8'
    ].map { |range| IPAddr.new(range) }.freeze

    module_function

    def queue_name(action)
      QUEUES.fetch(action.to_s)
    end

    def routing_key(action)
      ROUTING_KEYS.fetch(action.to_s)
    end

    def webhook_payload_for(delivery)
      event = delivery.event
      route = delivery.event_route
      receiver = delivery.notification_receiver
      target = delivery.notification_target
      receiver_target = delivery.notification_receiver_target || delivery.notification_receiver_action
      user = event.user
      vps = event.vps

      {
        event: {
          id: event.id,
          type: event.event_type,
          category: event.category,
          severity: event.severity,
          subject: event.subject,
          summary: event.summary,
          parameters: event.parameters || {},
          ip_addr: event.ip_addr,
          source: {
            class: event.source_class,
            id: event.source_id
          },
          user: user && {
            id: user.id,
            login: user.login
          },
          vps: vps && {
            id: vps.id,
            hostname: vps.hostname
          },
          created_at: event.created_at&.iso8601
        },
        delivery: {
          id: delivery.id,
          action: delivery.action,
          route: route && {
            id: route.id,
            label: route.display_label,
            matcher_summary: route.matcher_summary
          },
          receiver: receiver && {
            id: receiver.id,
            label: receiver.label
          },
          notification_target: target && {
            id: target.id,
            label: target.label,
            display_target: target.display_target
          },
          receiver_target: receiver_target && {
            id: receiver_target.id
          }
        }
      }
    end

    def telegram_payload_for(delivery)
      {
        chat_id: delivery.target_value
      }.merge(telegram_message_for(delivery))
    end

    def sms_payload_for(delivery)
      {
        to: delivery.target_value,
        text: sms_text_for(delivery),
        client_message_id: delivery.id.to_s,
        callback_url: sms_callback_url,
        callback_secret: sms_callback_secret
      }
    end

    def telegram_text_for(delivery)
      telegram_message_for(delivery).fetch(:text)
    end

    def telegram_message_for(delivery)
      event = delivery.event
      template_name = delivery.template_name.presence&.to_sym ||
                      VpsAdmin::API::Events.template_name_for(event, :telegram)

      if template_name
        rendered = ::NotificationTemplate.render_telegram!(
          template_name,
          VpsAdmin::API::Events.template_options_for(event, delivery, action: :telegram)
        )
        html = rendered[:html].to_s

        if html.present? && html.length <= TELEGRAM_TEXT_LIMIT
          return {
            text: html,
            parse_mode: TELEGRAM_HTML_PARSE_MODE,
            link_preview_options: TELEGRAM_LINK_PREVIEW_OPTIONS
          }
        end

        return { text: truncate_telegram_text(rendered.fetch(:text)) }
      end

      text_lines = [
        "[#{event.severity}] #{event.subject}",
        "Event: #{event.event_type}"
      ]
      html_lines = [
        "<b>#{telegram_html_escape("[#{event.severity}] #{event.subject}")}</b>",
        "Event: <code>#{telegram_html_escape(event.event_type)}</code>"
      ]

      if event.vps
        vps_label = "##{event.vps.id} #{event.vps.hostname}"
        text_lines << "VPS: #{vps_label}"
        html_lines << "VPS: #{telegram_html_escape(vps_label)}"
      end

      event_url = telegram_event_url(event)
      if event_url.present?
        text_lines << "Open: #{event_url}"
        html_lines << %(Open: <a href="#{telegram_html_escape(event_url)}">event detail</a>)
      end

      html = html_lines.join("\n")
      if html.length <= TELEGRAM_TEXT_LIMIT
        return {
          text: html,
          parse_mode: TELEGRAM_HTML_PARSE_MODE,
          link_preview_options: TELEGRAM_LINK_PREVIEW_OPTIONS
        }
      end

      { text: truncate_telegram_text(text_lines.join("\n")) }
    end

    def telegram_event_url(event)
      base_url = VpsAdmin::API::Events.webui_url
      return if base_url.blank?

      "#{base_url}/?page=notifications&action=event_show&id=#{event.id}"
    end

    def telegram_html_escape(value)
      ERB::Util.html_escape(value.to_s)
    end

    def truncate_telegram_text(text)
      text.to_s[0, TELEGRAM_TEXT_LIMIT]
    end

    def sms_text_for(delivery)
      event = delivery.event
      template_name = delivery.template_name.presence&.to_sym ||
                      VpsAdmin::API::Events.template_name_for(event, :sms)

      if template_name
        rendered = ::NotificationTemplate.render_sms!(
          template_name,
          VpsAdmin::API::Events.template_options_for(event, delivery, action: :sms)
        )
        return truncate_sms_text(rendered.fetch(:text))
      end

      lines = [
        "[#{event.severity}] #{event.subject}",
        "Event: #{event.event_type}"
      ]
      lines << "VPS: ##{event.vps.id} #{event.vps.hostname}" if event.vps

      truncate_sms_text(lines.join("\n"))
    end

    def truncate_sms_text(text)
      text.to_s[0, SMS_TEXT_LIMIT]
    end

    def telegram_configured?(config = Config.load)
      telegram = config.fetch('telegram', {})
      return false if telegram.has_key?('enabled') && !truthy_config?(telegram['enabled'])

      truthy_config?(telegram.fetch('configured', false)) ||
        telegram_config_has_token?(telegram)
    rescue KeyError
      false
    end

    def telegram_config_has_token?(telegram)
      telegram.fetch('bot_token', nil).present? ||
        telegram.fetch('bot_token_file', nil).present? ||
        ENV['VPSADMIN_TELEGRAM_BOT_TOKEN'].present? ||
        ENV['VPSADMIN_TELEGRAM_BOT_TOKEN_FILE'].present?
    end

    def sms_configured?(config = Config.load)
      sms = config.fetch('sms', {})
      return false if sms.has_key?('enabled') && !truthy_config?(sms['enabled'])

      truthy_config?(sms.fetch('configured', false)) || sms_gateways(sms).any?
    rescue KeyError
      false
    end

    def send_sms_verification_code!(action)
      action.ensure_sms_verification_code!
      body = JSON.dump({
                         to: action.target_value,
                         text: sms_verification_text(action),
                         client_message_id: "#{SMS_VERIFICATION_CLIENT_ID_PREFIX}#{action.id}"
                       })
      post_sms_to_gateway!(body)
      action.mark_sms_verification_sent!
    end

    def send_email_verification!(target)
      target.ensure_email_verification_token!
      mail_log = ::NotificationTemplate.send_custom_email(
        user: target.user,
        from: VpsAdmin::API::NotificationTemplates.default_from,
        to: [target.target_value],
        subject: 'Verify your vpsAdmin notification e-mail target',
        text_plain: email_verification_text(target)
      )
      deliver_mail_log!(mail_log)
      target.mark_email_verification_sent!
      target.update!(last_error: nil)
      mail_log
    rescue StandardError => e
      target&.update(last_error: e.message) if target&.persisted?
      raise EmailVerificationDeliveryError, e.message
    end

    def deliver_mail_log!(mail_log, config: Config.load)
      delivery = Struct.new(:mail_log).new(mail_log)
      Dispatcher.new('email', config:).send(:deliver_email, delivery)
    end

    def sms_callback_secret
      SecureRandom.hex(32)
    end

    def apply_sms_gateway_callback!(payload, raw_body: nil, headers: {}, authorization: nil,
                                    request_method: 'POST', request_path: SMS_CALLBACK_PATH,
                                    now: Time.now)
      payload = payload.to_h
      client_message_id = payload.fetch('client_message_id').to_s
      unless client_message_id.match?(/\A[0-9]+\z/)
        raise SmsCallbackAuthenticationError, 'Invalid SMS callback authorization'
      end

      delivery = ::EventDelivery.find_by(id: client_message_id)
      unless delivery&.sms_action?
        raise SmsCallbackAuthenticationError, 'Invalid SMS callback authorization'
      end

      verify_sms_gateway_callback!(
        delivery,
        raw_body || JSON.dump(payload),
        headers:,
        authorization:,
        request_method:,
        request_path:,
        now:
      )

      status = payload.fetch('status').to_s

      delivery.with_lock do
        if delivery.sent_state? || delivery.failed_state?
          unless delivery.state == status
            raise SmsCallbackConflictError, 'SMS delivery already has a different final state'
          end

          return delivery
        end

        now = Time.now
        attrs = {
          response_status: 200,
          response_body: truncate_response_body(JSON.dump(payload)),
          provider_message_id: sms_callback_provider_message_id(payload) || delivery.provider_message_id,
          last_attempt_at: now,
          updated_at: now
        }

        case status
        when 'sent'
          attrs[:state] = 'sent'
          attrs[:next_attempt_at] = nil
          attrs[:error_summary] = nil
        when 'failed'
          attrs[:state] = 'failed'
          attrs[:next_attempt_at] = nil
          attrs[:error_summary] = payload['error_summary'].presence || 'SMS gateway reported final failure'
        else
          raise ArgumentError, "unsupported SMS status #{status.inspect}"
        end

        delivery.update!(attrs)
      end
      delivery
    end

    def verify_sms_gateway_callback!(delivery, raw_body, headers:, authorization:, request_method:, request_path:, now:)
      secret = sms_callback_secret_for_delivery(delivery)
      if secret.present?
        verify_sms_gateway_callback_hmac!(
          secret,
          raw_body,
          headers:,
          request_method:,
          request_path:,
          now:
        )
      else
        verify_legacy_sms_gateway_callback!(authorization)
      end
    end

    def verify_legacy_sms_gateway_callback!(authorization)
      token = sms_callback_token
      return if token.present? && secure_compare(authorization.to_s, "Bearer #{token}")

      raise SmsCallbackAuthenticationError, 'Invalid SMS callback authorization'
    end

    def verify_sms_gateway_callback_hmac!(secret, raw_body, headers:, request_method:, request_path:, now:)
      version = sms_callback_header(headers, 'X-VpsAdmin-SMS-Signature-Version').to_s
      timestamp_raw = sms_callback_header(headers, 'X-VpsAdmin-SMS-Timestamp').to_s
      signature = sms_callback_header(headers, 'X-VpsAdmin-SMS-Signature').to_s

      unless version == SMS_CALLBACK_SIGNATURE_VERSION
        raise SmsCallbackAuthenticationError, 'Invalid SMS callback signature version'
      end

      timestamp = Time.iso8601(timestamp_raw)
      if timestamp < now - SMS_CALLBACK_SIGNATURE_TOLERANCE ||
         timestamp > now + SMS_CALLBACK_SIGNATURE_TOLERANCE
        raise SmsCallbackAuthenticationError, 'Stale SMS callback timestamp'
      end

      body_hash = Digest::SHA256.hexdigest(raw_body.to_s)
      signature_input = [
        SMS_CALLBACK_SIGNATURE_VERSION,
        request_method.to_s.upcase,
        request_path.presence || '/',
        timestamp_raw,
        body_hash
      ].join("\n")
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, signature_input)}"
      unless secure_compare(signature, expected)
        raise SmsCallbackAuthenticationError, 'Invalid SMS callback signature'
      end
    rescue ArgumentError
      raise SmsCallbackAuthenticationError, 'Invalid SMS callback timestamp'
    end

    def sms_callback_header(headers, name)
      headers[name] ||
        headers[name.downcase] ||
        headers["HTTP_#{name.upcase.tr('-', '_')}"]
    end

    def sms_callback_secret_for_delivery(delivery)
      payload = JSON.parse(delivery.payload.to_s)
      return unless payload.is_a?(Hash)

      payload['callback_secret'].presence
    rescue JSON::ParserError
      nil
    end

    def secure_compare(left, right)
      left = left.to_s
      right = right.to_s
      return false unless left.bytesize == right.bytesize

      OpenSSL.fixed_length_secure_compare(left, right)
    end

    def sms_callback_provider_message_id(payload)
      gateway = payload['gateway'].presence
      provider_id = payload['provider_id'].presence || payload['gateway_message_id'].presence
      [gateway, provider_id].compact.join(':').presence
    end

    def truncate_response_body(body)
      return if body.nil?

      body.to_s.byteslice(0, RESPONSE_BODY_LIMIT).to_s.scrub
    end

    def post_sms_to_gateway!(body, sms: sms_config)
      gateways = sms_gateways(sms)
      raise SmsGatewayResponseError.new(nil, nil, 'SMS gateways are not configured') if gateways.empty?

      last_error = nil
      gateways.each do |gateway|
        response = post_sms_gateway_request(gateway, body)
        if response.code.to_i.between?(200, 299)
          return sms_gateway_success(gateway, response)
        end

        last_error = SmsGatewayResponseError.new(
          response.code.to_i,
          truncate_response_body(response.body),
          "SMS gateway #{gateway.fetch('name')} returned HTTP #{response.code}"
        )
      rescue StandardError => e
        last_error = SmsGatewayResponseError.new(nil, nil, "SMS gateway #{gateway.fetch('name')} failed: #{e.message}")
      end

      raise last_error || SmsGatewayResponseError.new(nil, nil, 'SMS gateways are not configured')
    end

    def post_sms_gateway_request(gateway, body)
      uri = URI.parse(gateway.fetch('url'))
      raise ArgumentError, 'SMS gateway URL must use HTTP or HTTPS' unless uri.is_a?(URI::HTTP) && uri.host.present?

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{gateway.fetch('token')}"
      request.body = body

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: sms_open_timeout,
        read_timeout: sms_read_timeout
      ) do |http|
        http.request(request)
      end
    end

    def sms_gateway_success(gateway, response)
      body = JSON.parse(response.body.to_s)
      id = body['id'] || Array(body['message_ids']).first

      {
        gateway: gateway.fetch('name'),
        provider_message_id: [gateway.fetch('name'), id].compact.join(':').presence,
        response_status: response.code.to_i,
        response_body: truncate_response_body(response.body)
      }
    rescue JSON::ParserError
      {
        gateway: gateway.fetch('name'),
        provider_message_id: gateway.fetch('name'),
        response_status: response.code.to_i,
        response_body: truncate_response_body(response.body)
      }
    end

    def sms_gateways(sms = sms_config)
      raw = Array(sms['gateways'])
      if raw.empty? && sms['url'].present?
        raw = [
          {
            'name' => sms.fetch('name', 'default'),
            'url' => sms['url'],
            'token' => sms['token']
          }
        ]
      end

      raw.filter_map.with_index do |gateway, index|
        gateway = gateway.to_h
        url = gateway['url'].presence || gateway['endpoint'].presence
        token = gateway['token'].presence
        next if url.blank? || token.blank?

        {
          'name' => gateway['name'].presence || "gateway-#{index + 1}",
          'url' => url,
          'token' => token
        }
      end
    end

    def sms_config
      Config.load.fetch('sms', {})
    end

    def sms_callback_url
      configured = sms_config['callback_url'].presence
      return configured if configured

      api_url = ::SysConfig.get(:core, :api_url).to_s.chomp('/')
      return if api_url.blank?

      "#{api_url}#{SMS_CALLBACK_PATH}"
    rescue StandardError
      nil
    end

    def sms_callback_token
      sms_config['callback_token'].presence || ENV['VPSADMIN_SMS_CALLBACK_TOKEN'].presence
    end

    def sms_verification_text(action)
      template = sms_config.fetch('verification_text', 'Your vpsAdmin verification code is %{code}')
      format(template, code: action.send(:raw_verification_token))
    end

    def email_verification_text(target)
      [
        'A vpsAdmin notification target was created for this e-mail address.',
        'Open the link below to verify that notifications may be delivered here:',
        email_verification_url(target),
        "Target: #{target.label} <#{target.target_value}>",
        'The verification link expires in 24 hours.'
      ].join("\n\n")
    end

    def email_verification_url(target)
      token = target.send(:raw_verification_token)
      base_url = VpsAdmin::API::Events.webui_url
      raise 'WebUI URL is not configured' if base_url.blank?
      raise 'verification token is missing' if token.blank?

      query = URI.encode_www_form(
        page: 'notifications',
        action: 'target_email_confirm',
        id: target.id,
        token:
      )
      "#{base_url}/?#{query}"
    end

    def sms_open_timeout
      sms_config.fetch('open_timeout', 5).to_i
    end

    def sms_read_timeout
      sms_config.fetch('read_timeout', 15).to_i
    end

    def truthy_config?(value)
      value == true || value.to_s.casecmp('true') == 0 || value.to_s == '1'
    end

    def render_email_delivery!(delivery)
      unless delivery.notification_receiver_available?
        delivery.update!(
          state: 'canceled',
          error_summary: 'notification receiver is disabled or muted'
        )
        return
      end

      unless delivery.delivery_method_enabled?
        delivery.update!(
          state: 'canceled',
          error_summary: 'email delivery method is disabled'
        )
        return
      end

      unless delivery.receiver_action_available?
        delivery.update!(
          state: 'canceled',
          error_summary: 'e-mail action is not available'
        )
        return
      end

      mail_log = build_mail_log(delivery)

      if mail_log.nil?
        delivery.update!(
          state: 'skipped',
          error_summary: 'notification template is disabled'
        )
        return
      end

      persist_mail_log_snapshot!(mail_log)

      delivery.update!(
        mail_log:,
        error_summary: nil
      )
    rescue StandardError => e
      delivery.update!(
        state: 'failed',
        error_summary: "#{e.class}: #{e.message}"
      )
    end

    def build_mail_log(delivery)
      event = delivery.event
      template_name = delivery.template_name.presence&.to_sym ||
                      VpsAdmin::API::Events.template_name_for(event)

      if template_name
        return ::NotificationTemplate.send_email!(
          template_name,
          VpsAdmin::API::Events.template_options_for(event, delivery)
        )
      end

      ::NotificationTemplate.send_custom_email(
        VpsAdmin::API::Events.email_custom_options_for(event, delivery)
      )
    end

    def persist_mail_log_snapshot!(mail_log)
      %w[to cc bcc].each do |attr|
        mail_log.public_send("#{attr}=", '') if mail_log.public_send(attr).nil?
      end

      mail_log.save!(validate: false) unless mail_log.persisted?
    end

    Actions.define :email do
      label 'E-mail'
      target_kind :default_recipient, label: 'default recipient'
      target_kind :custom, label: 'custom target'

      validate_receiver_action do
        check_email_target
      end

      display_target do
        target_value.presence || 'Account e-mail'
      end

      receiver_action_available do
        email_action? && (!email_verification_required? || verified?)
      end

      plan_delivery do |route, receiver, receiver_action|
        email_delivery(route, receiver, receiver_action)
      end

      prepare_delivery do |delivery|
        VpsAdmin::API::Notifications.render_email_delivery!(delivery)
      end

      deliver do |delivery|
        deliver_email(delivery)
      end
    end

    Actions.define :webhook do
      label 'Webhook'
      target_kind :custom, label: 'custom target'

      validate_receiver_action do
        check_webhook_target
      end

      display_target do
        target_value.presence || 'Webhook URL'
      end

      receiver_action_available do
        webhook_action? && target_value.present?
      end

      plan_delivery do |route, receiver, receiver_action|
        webhook_delivery(route, receiver, receiver_action)
      end

      prepare_delivery do |delivery|
        if delivery.payload.blank?
          delivery.update!(payload: JSON.dump(VpsAdmin::API::Notifications.webhook_payload_for(delivery)))
        end
      end

      deliver do |delivery|
        deliver_webhook(delivery)
      end
    end

    Actions.define :telegram do
      label 'Telegram'
      target_kind :custom, label: 'custom target'

      available do
        VpsAdmin::API::Notifications.telegram_configured?
      end

      validate_receiver_action do
        check_telegram_target
      end

      display_target do
        if target_value.present?
          "Telegram chat #{target_value}"
        else
          'Linked Telegram chat'
        end
      end

      receiver_action_available do
        telegram_action? && verified? && target_value.present?
      end

      plan_delivery do |route, receiver, receiver_action|
        telegram_delivery(route, receiver, receiver_action)
      end

      prepare_delivery do |delivery|
        if delivery.payload.blank?
          delivery.update!(payload: JSON.dump(VpsAdmin::API::Notifications.telegram_payload_for(delivery)))
        end
      end

      deliver do |delivery|
        deliver_telegram(delivery)
      end
    end

    Actions.define :sms do
      label 'SMS'
      target_kind :custom, label: 'custom target'

      available do
        VpsAdmin::API::Notifications.sms_configured?
      end

      validate_receiver_action do
        check_sms_target
      end

      display_target do
        target_value.presence || 'Phone number'
      end

      receiver_action_available do
        sms_action? && verified? && target_value.present?
      end

      plan_delivery do |route, receiver, receiver_action|
        sms_delivery(route, receiver, receiver_action)
      end

      prepare_delivery do |delivery|
        if delivery.payload.blank?
          delivery.update!(payload: JSON.dump(VpsAdmin::API::Notifications.sms_payload_for(delivery)))
        end
      end

      deliver do |delivery|
        deliver_sms(delivery)
      end
    end

    class Config
      class << self
        def load(path = default_path)
          return {} unless File.exist?(path)

          YAML.safe_load_file(path, aliases: true) || {}
        end

        def default_path
          ENV['VPSADMIN_NOTIFICATIONS_CONFIG'].presence ||
            File.join(VpsAdmin::API.root, 'config', 'notifications.yml')
        end
      end
    end

    module RateLimits
      PERIODS = {
        'minute' => 60,
        'hour' => 60 * 60,
        'day' => 24 * 60 * 60,
        'week' => 7 * 24 * 60 * 60
      }.freeze
      PERIOD_LABELS = {
        'minute' => 'minute',
        'hour' => 'hour',
        'day' => 'day',
        'week' => 'week'
      }.freeze
      DEFAULT_LIMITS = {
        'email' => {
          'minute' => 30,
          'hour' => 300,
          'day' => 2000,
          'week' => 5000
        },
        'webhook' => {
          'minute' => 60,
          'hour' => 1000,
          'day' => 10_000,
          'week' => 25_000
        },
        'telegram' => {
          'minute' => 20,
          'hour' => 200,
          'day' => 1000,
          'week' => 2500
        },
        'sms' => {
          'minute' => 3,
          'hour' => 30,
          'day' => 150,
          'week' => 300
        }
      }.freeze

      module_function

      def periods
        PERIODS.keys
      end

      def period_labels
        PERIOD_LABELS
      end

      def default_limits(config = Config.load)
        configured = rate_limit_config(config).fetch('defaults', {})
        defaults = deep_dup(DEFAULT_LIMITS)

        configured.each do |delivery_method, periods|
          delivery_method = delivery_method.to_s
          next unless defaults.has_key?(delivery_method)
          next unless periods.is_a?(Hash)

          periods.each do |period, count|
            period = period.to_s
            next unless PERIODS.has_key?(period)

            value = Integer(count)
            defaults[delivery_method][period] = value if value > 0
          rescue ArgumentError, TypeError
            next
          end
        end

        defaults
      end

      def limit_count(user, delivery_method, period, config: Config.load)
        delivery_method = delivery_method.to_s
        period = period.to_s

        override = user.user_notification_rate_limits.find_by(
          delivery_method:,
          period:
        )
        override&.limit_count || default_limits(config).dig(delivery_method, period)
      end

      def rate_limited_until(delivery, config: Config.load, now: Time.now)
        with_limit_lock(delivery) do
          rate_limited_until_without_lock(delivery, config:, now:)
        end
      end

      def with_limit_lock(delivery, &)
        user = delivery.recipient_user
        return yield unless user

        state = state_for(user, delivery.action)

        state.with_lock(&)
      end

      def rate_limited_until_without_lock(delivery, config: Config.load, now: Time.now)
        user = delivery.recipient_user
        return unless user

        limited_until = periods.filter_map do |period|
          limited_until_for(user, delivery.action, period, config:, now:)
        end.max

        limited_until if limited_until && limited_until > now
      end

      def usage_count(user, delivery_method, period, now: Time.now)
        seconds = PERIODS.fetch(period.to_s)
        ::EventDeliveryAttempt
          .where(
            recipient_user_id: user.id,
            action: delivery_method.to_s,
            started_at: (now - seconds)..now
          )
          .count
      end

      def next_reset_at(user, delivery_method, period, now: Time.now)
        seconds = PERIODS.fetch(period.to_s)
        started_at = ::EventDeliveryAttempt
                     .where(
                       recipient_user_id: user.id,
                       action: delivery_method.to_s,
                       started_at: (now - seconds)..now
                     )
                     .order(:started_at)
                     .limit(1)
                     .pluck(:started_at)
                     .first
        started_at && (started_at + seconds)
      end

      def limited_until_for(user, delivery_method, period, config:, now:)
        limit = limit_count(user, delivery_method, period, config:)
        return unless limit

        count = usage_count(user, delivery_method, period, now:)
        return if count < limit

        reset_after_attempts = count - limit
        reset_started_at = attempts_in_window(user, delivery_method, period, now:)
                           .offset(reset_after_attempts)
                           .limit(1)
                           .pluck(:started_at)
                           .first
        reset_started_at && (reset_started_at + PERIODS.fetch(period.to_s))
      end

      def attempts_in_window(user, delivery_method, period, now:)
        seconds = PERIODS.fetch(period.to_s)
        ::EventDeliveryAttempt
          .where(
            recipient_user_id: user.id,
            action: delivery_method.to_s,
            started_at: (now - seconds)..now
          )
          .order(:started_at)
      end

      def state_for(user, delivery_method)
        ::NotificationRateLimitState.find_or_create_by!(
          user:,
          delivery_method: delivery_method.to_s
        )
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def rate_limit_config(config)
        config.fetch('rate_limits', {})
      end

      def deep_dup(value)
        Marshal.load(Marshal.dump(value))
      end
    end

    class Publisher
      class << self
        def default
          @default ||= new
        end
      end

      def initialize(config: Config.load)
        @config = config
        @connection = nil
      end

      def publish_after_commit(deliveries)
        deliveries = Array(deliveries).select { |delivery| delivery.action.in?(QUEUES.keys) }
        return if deliveries.empty?

        if ActiveRecord.respond_to?(:after_all_transactions_commit)
          ActiveRecord.after_all_transactions_commit { publish(deliveries) }
        else
          publish(deliveries)
        end
      end

      def publish(deliveries)
        return unless rabbitmq_configured?

        channel = connection.create_channel
        exchange = channel.direct(EXCHANGE_NAME, durable: true)

        deliveries.group_by(&:action).each_key do |action|
          declare_queue(channel, exchange, action)
        end

        deliveries.each do |delivery|
          exchange.publish(
            JSON.dump({
                        delivery_id: delivery.id,
                        action: delivery.action,
                        released_at: delivery.released_at&.iso8601
                      }),
            routing_key: Notifications.routing_key(delivery.action),
            persistent: true
          )
        end
      rescue StandardError => e
        warn "Unable to notify event delivery dispatchers: #{e.class}: #{e.message}"
      ensure
        channel.close if channel && channel.respond_to?(:open?) && channel.open?
      end

      protected

      def declare_queue(channel, exchange, action)
        queue = channel.queue(
          Notifications.queue_name(action),
          durable: true,
          arguments: { 'x-queue-type' => 'quorum' }
        )
        queue.bind(exchange, routing_key: Notifications.routing_key(action))
      end

      def connection
        if @connection.nil? || !@connection.open?
          rabbitmq = rabbitmq_config
          @connection = Bunny.new(
            hosts: Array(rabbitmq.fetch('hosts')),
            vhost: rabbitmq.fetch('vhost', '/'),
            username: rabbitmq.fetch('username'),
            password: rabbitmq.fetch('password'),
            log_file: $stderr
          )
          @connection.start
        end

        @connection
      end

      def rabbitmq_configured?
        rabbitmq_config
        true
      rescue KeyError
        false
      end

      def rabbitmq_config
        rabbitmq = @config.fetch('rabbitmq')
        rabbitmq.fetch('hosts')
        rabbitmq.fetch('username')
        rabbitmq.fetch('password')
        rabbitmq
      end
    end

    class Release
      class << self
        def release!(deliveries, publisher: Publisher.default)
          ids = Array(deliveries)
                .map { |delivery| delivery.respond_to?(:id) ? delivery.id : delivery }
                .map(&:to_i)
                .uniq
          return [] if ids.empty?

          now = Time.now
          released = []

          ::EventDelivery.transaction do
            released = ::EventDelivery
                       .where(id: ids, state: 'prepared')
                       .order(:id)
                       .to_a
            next if released.empty?

            ::EventDelivery.where(id: released.map(&:id)).update_all(
              state: ::EventDelivery.states.fetch('released'),
              released_at: now,
              next_attempt_at: now,
              updated_at: now
            )

            released.each do |delivery|
              delivery.state = 'released'
              delivery.released_at = now
              delivery.next_attempt_at = now
            end
          end

          publisher.publish_after_commit(released)
          released
        end
      end
    end

    class Retry
      class InvalidState < StandardError; end

      class << self
        def retry!(delivery, publisher: Publisher.default)
          now = Time.now

          delivery.with_lock do
            delivery.reload
            unless delivery.failed_state?
              raise InvalidState, 'only failed deliveries can be retried'
            end

            delivery.update!(
              state: 'released',
              next_attempt_at: now,
              error_summary: nil
            )
          end

          publisher.publish_after_commit([delivery])
          delivery
        end
      end
    end

    class Dispatcher
      STOP_WORKER = Object.new.freeze

      def self.run(action)
        new(action).run
      end

      def self.dispatch_due(action, **)
        new(action).dispatch_due(**)
      end

      def initialize(
        action,
        config: Config.load,
        monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
        sleeper: ->(seconds) { sleep(seconds) }
      )
        @action = action.to_s
        unless Actions.known?(@action) && QUEUES.has_key?(@action)
          raise ArgumentError, "unsupported notification action #{@action}"
        end

        @config = config
        @monotonic_clock = monotonic_clock
        @sleeper = sleeper
        @running = true
        @long_running = false
        @delivery_queue = Queue.new
        @delayed_delivery_ids = []
        @queued_delivery_ids = Set.new
        @pool_mutex = Mutex.new
        @pool_condition = ConditionVariable.new
        @delayed_condition = ConditionVariable.new
        @in_flight = 0
        @workers = nil
        @delayed_scheduler = nil
        @stopping_workers = false
      end

      def run
        trap_signals
        @long_running = true
        start_workers unless inline_delivery_dispatch?

        if rabbitmq_configured?
          run_with_rabbitmq
        else
          run_reconciliation_loop
        end
      ensure
        stop_workers
      end

      def dispatch_due(limit: limit_value, wait: true)
        requested_limit = limit.to_i
        delivery_limit = available_delivery_limit(requested_limit)
        return if delivery_limit <= 0

        deliveries = ActiveRecord::Base.connection_pool.with_connection do
          due_deliveries(delivery_limit, scan_limit: requested_limit)
        end

        if inline_delivery_dispatch?
          worker_state = {}
          deliveries.each { |delivery| dispatch_delivery(delivery, worker_state:) }
          return
        end

        deliveries.each { |delivery| submit_delivery_id(delivery.id) }
        wait_for_idle if wait
      ensure
        stop_workers if wait && !@long_running
      end

      def dispatch_delivery_id(id, worker_state: nil, defer_throttles: false)
        return if id.blank?

        delivery = find_delivery(id)
        return unless delivery && delivery.action == @action

        dispatch_delivery(delivery, worker_state:, defer_throttles:)
      end

      protected

      def due_deliveries(limit, scan_limit: limit)
        return due_delivery_scope.limit(limit).to_a unless email_due_selection?

        select_due_email_deliveries(limit, scan_limit:)
      end

      def due_delivery_scope
        scope = ::EventDelivery
                .includes(
                  :event,
                  :mail_log,
                  :event_route,
                  :notification_receiver,
                  :notification_target,
                  :notification_receiver_action
                )
                .where(action: @action, state: %w[released sending])
                .due
                .order(:id)

        excluded_ids = queued_delivery_ids
        excluded_ids.empty? ? scope : scope.where.not(id: excluded_ids)
      end

      def email_due_selection?
        @action == 'email' && email_domain_min_delivery_interval > 0
      end

      def select_due_email_deliveries(limit, scan_limit:)
        limit = limit.to_i
        scan_limit = [scan_limit.to_i, limit].max
        max_scan = email_due_scan_limit(scan_limit)
        selected = []
        overflow = []
        seen_domains = Set.new
        last_id = nil
        scanned = 0

        loop do
          batch_limit = [scan_limit, max_scan - scanned].min
          break if batch_limit <= 0

          batch_scope = due_delivery_scope
          batch_scope = batch_scope.where('event_deliveries.id > ?', last_id) if last_id
          batch = batch_scope.limit(batch_limit).to_a
          break if batch.empty?

          scanned += batch.size

          batch.each do |delivery|
            last_id = delivery.id
            domains = email_recipient_domains(delivery)

            if email_domains_available?(domains) && domains.any? { |domain| !seen_domains.include?(domain) }
              selected << delivery
              seen_domains.merge(domains)
              return selected if selected.size >= limit
            elsif overflow.size < limit
              overflow << delivery
            end
          end

          break if batch.size < batch_limit
        end

        selected.concat(overflow.first(limit - selected.size)) if selected.size < limit
        selected
      end

      def email_due_scan_limit(scan_limit)
        scan_limit * EMAIL_DUE_SCAN_MULTIPLIER
      end

      def email_domains_available?(domains)
        email_domain_limiter.delay_for(domains) <= 0
      end

      def queued_delivery_ids
        @pool_mutex.synchronize { @queued_delivery_ids.to_a }
      end

      def available_delivery_limit(requested_limit)
        limit = requested_limit.to_i
        return limit if inline_delivery_dispatch?

        @pool_mutex.synchronize do
          [limit, max_in_flight - @in_flight].min
        end
      end

      def max_in_flight
        limit_value
      end

      def find_delivery(id)
        ::EventDelivery
          .includes(
            :event,
            :mail_log,
            :event_route,
            :notification_receiver,
            :notification_target,
            :notification_receiver_action
          )
          .find_by(id:)
      end

      def run_with_rabbitmq
        channel = connection.create_channel
        exchange = channel.direct(EXCHANGE_NAME, durable: true)
        queue = channel.queue(
          Notifications.queue_name(@action),
          durable: true,
          arguments: { 'x-queue-type' => 'quorum' }
        )
        queue.bind(exchange, routing_key: Notifications.routing_key(@action))

        while @running
          dispatch_due(wait: false)

          delivery_info, _properties, payload = queue.pop(manual_ack: true)

          if delivery_info
            handle_queue_payload(channel, delivery_info, payload)
          else
            sleep poll_interval
          end
        end
      ensure
        channel.close if channel && channel.respond_to?(:open?) && channel.open?
      end

      def handle_queue_payload(channel, delivery_info, payload)
        data = JSON.parse(payload)
        if inline_delivery_dispatch?
          ActiveRecord::Base.connection_pool.with_connection do
            dispatch_delivery_id(data['delivery_id'], defer_throttles: false)
          end
        else
          submit_delivery_id(data['delivery_id'])
        end
        channel.ack(delivery_info.delivery_tag)
      rescue StandardError => e
        warn "Unable to process notification delivery message: #{e.class}: #{e.message}"
        channel.nack(delivery_info.delivery_tag, false, true)
      end

      def run_reconciliation_loop
        while @running
          dispatch_due
          sleep poll_interval
        end
      end

      def dispatch_delivery(delivery, worker_state: nil, defer_throttles: false)
        if @action == 'email'
          if defer_throttles
            delay = email_throttle_delay(delivery, worker_state)
            return delay if delay
          else
            wait_for_email_throttles!(delivery, worker_state)
          end
        end

        attempt = claim_delivery(delivery)
        return unless attempt

        result = deliver(delivery.reload)
        if result&.fetch(:accepted, false)
          mark_accepted!(delivery, attempt, result)
        else
          mark_success!(delivery, attempt, result)
        end
        nil
      rescue WebhookResponseError => e
        mark_failure!(
          delivery,
          attempt,
          response_status: e.response_status,
          response_body: e.response_body,
          response_headers: e.response_headers,
          error_summary: e.message
        )
        nil
      rescue TelegramResponseError, SmsGatewayResponseError => e
        mark_failure!(
          delivery,
          attempt,
          response_status: e.response_status,
          response_body: e.response_body,
          error_summary: e.message
        )
        nil
      rescue StandardError => e
        mark_failure!(
          delivery,
          attempt,
          response_status: exception_response_status(e),
          response_body: exception_response_body(e),
          error_summary: "#{e.class}: #{e.message}"
        )
        nil
      end

      def submit_delivery_id(id)
        return false if id.blank?

        delivery_id = id.to_i
        return false if delivery_id <= 0

        start_workers
        return false unless reserve_delivery_id(delivery_id)

        @delivery_queue << delivery_id
        true
      rescue StandardError
        release_delivery_id(delivery_id) if delivery_id
        raise
      end

      def reserve_delivery_id(delivery_id)
        @pool_mutex.synchronize do
          return false if @queued_delivery_ids.include?(delivery_id)
          return false if @in_flight >= max_in_flight

          @queued_delivery_ids.add(delivery_id)
          @in_flight += 1
          true
        end
      end

      def release_delivery_id(delivery_id)
        @pool_mutex.synchronize do
          @queued_delivery_ids.delete(delivery_id)
          @in_flight -= 1 if @in_flight > 0
          @pool_condition.broadcast if @in_flight == 0
        end
      end

      def start_workers
        @pool_mutex.synchronize do
          return if @workers

          @stopping_workers = false
          @delayed_scheduler = Thread.new { delayed_scheduler_loop }
          @workers = Array.new(concurrency) do |index|
            Thread.new { worker_loop(index + 1) }
          end
        end
      end

      def stop_workers
        workers, delayed_scheduler = @pool_mutex.synchronize do
          ret_workers = @workers
          ret_scheduler = @delayed_scheduler
          @workers = nil
          @delayed_scheduler = nil
          @stopping_workers = true
          @delayed_condition.broadcast
          [ret_workers, ret_scheduler]
        end

        delayed_scheduler&.join

        if workers
          workers.length.times { @delivery_queue << STOP_WORKER }
          workers.each(&:join)
        end
        nil
      end

      def wait_for_idle
        @pool_mutex.synchronize do
          @pool_condition.wait(@pool_mutex) while @in_flight > 0
        end
      end

      def worker_loop(index)
        worker_state = { index: }

        loop do
          delivery_id = @delivery_queue.pop
          break if delivery_id.equal?(STOP_WORKER)

          delay = nil
          begin
            ActiveRecord::Base.connection_pool.with_connection do
              delay = dispatch_delivery_id(
                delivery_id,
                worker_state:,
                defer_throttles: true
              )
            end
          rescue StandardError => e
            warn "Unable to process notification delivery #{delivery_id}: #{e.class}: #{e.message}"
          ensure
            if delay.is_a?(Numeric) && delay > 0
              defer_delivery_id(delivery_id, delay)
            else
              release_delivery_id(delivery_id)
            end
          end
        end
      end

      def defer_delivery_id(delivery_id, delay)
        ready_at = monotonic_time + delay

        @pool_mutex.synchronize do
          if @stopping_workers
            @queued_delivery_ids.delete(delivery_id)
            @in_flight -= 1 if @in_flight > 0
            @pool_condition.broadcast if @in_flight == 0
            return
          end

          @delayed_delivery_ids << [ready_at, delivery_id]
          @delayed_delivery_ids.sort_by!(&:first)
          @delayed_condition.signal
        end
      end

      def delayed_scheduler_loop
        loop do
          delivery_id = nil

          @pool_mutex.synchronize do
            loop do
              return if @stopping_workers

              if @delayed_delivery_ids.empty?
                @delayed_condition.wait(@pool_mutex)
                next
              end

              ready_at, id = @delayed_delivery_ids.first
              wait_for = ready_at - monotonic_time

              if wait_for <= 0
                @delayed_delivery_ids.shift
                delivery_id = id
                break
              end

              @delayed_condition.wait(@pool_mutex, wait_for)
            end
          end

          @delivery_queue << delivery_id if delivery_id
        end
      end

      def wait_for_email_throttles!(delivery, worker_state)
        loop do
          delay = email_throttle_delay(delivery, worker_state)
          return unless delay

          sleep_seconds(delay)
        end
      end

      def email_throttle_delay(delivery, worker_state)
        worker_delay = email_worker_delay_delay(worker_state)
        return worker_delay if worker_delay

        domain_delay = email_domain_limiter.reserve_or_delay(
          email_recipient_domains(delivery)
        )
        return domain_delay if domain_delay > 0

        worker_state[:last_email_started_at] = monotonic_time if worker_state
        nil
      end

      def email_worker_delay_delay(worker_state)
        return unless worker_state && email_worker_delay > 0

        last_started_at = worker_state[:last_email_started_at]
        return unless last_started_at

        wait_for = last_started_at + email_worker_delay - monotonic_time
        wait_for if wait_for > 0
      end

      def email_domain_limiter
        @email_domain_limiter ||= DomainRateLimiter.new(
          interval: email_domain_min_delivery_interval,
          clock: @monotonic_clock,
          sleeper: @sleeper
        )
      end

      def email_recipient_domains(delivery)
        mail_log = delivery.mail_log
        domains = %i[to cc bcc].flat_map do |attr|
          email_address_domains(mail_log&.public_send(attr))
        end

        domains.uniq.presence || ['_unknown']
      end

      def email_address_domains(value)
        return [] if value.blank?

        ::Mail::AddressList
          .new(value)
          .addresses
          .filter_map { |address| normalize_email_domain(address.domain) }
      rescue StandardError
        ['_unknown']
      end

      def normalize_email_domain(domain)
        ret = domain.to_s.strip.downcase.sub(/\.\z/, '')
        ret.presence
      end

      def claim_delivery(delivery)
        attempt = nil

        delivery.with_lock do
          next unless delivery.action == @action
          next unless delivery.due_for_delivery?

          unless delivery.notification_receiver_available?
            delivery.update!(
              state: 'canceled',
              error_summary: 'notification receiver is disabled or muted'
            )
            next
          end

          unless delivery.delivery_method_enabled?
            delivery.update!(
              state: 'canceled',
              error_summary: "#{@action} delivery method is disabled"
            )
            next
          end

          unless delivery.receiver_action_available?
            delivery.update!(
              state: 'canceled',
              error_summary: "#{@action} action is not available"
            )
            next
          end

          RateLimits.with_limit_lock(delivery) do
            limited_until = RateLimits.rate_limited_until_without_lock(delivery, config: @config)
            if limited_until
              delivery.update!(
                state: 'released',
                next_attempt_at: limited_until,
                error_summary: "delivery rate limit reached; next attempt after #{limited_until.iso8601}"
              )
              next
            end

            attempt_number = delivery.attempt_count + 1
            mark_stale_attempts_failed!(delivery) if delivery.sending_state?

            attempt = delivery.event_delivery_attempts.create!(
              action: delivery.action,
              recipient_user: delivery.recipient_user,
              state: 'running',
              attempt_number:,
              started_at: Time.now
            )

            delivery.update!(
              state: 'sending',
              attempt_count: attempt_number,
              last_attempt_at: Time.now,
              next_attempt_at: Time.now + CLAIM_TIMEOUT,
              error_summary: nil
            )
          end
        end

        attempt
      end

      def mark_stale_attempts_failed!(delivery)
        now = Time.now
        delivery.event_delivery_attempts
                .where(state: ::EventDeliveryAttempt.states.fetch('running'))
                .where(finished_at: nil)
                .update_all(
                  state: ::EventDeliveryAttempt.states.fetch('failed'),
                  finished_at: now,
                  error_summary: 'delivery attempt timed out',
                  updated_at: now
                )
      end

      def deliver(delivery)
        Actions.fetch(@action).deliver_with(self, delivery)
      end

      def deliver_email(delivery)
        mail_log = delivery.mail_log
        raise 'delivery has no rendered e-mail' unless mail_log

        message = ::Mail.new
        message.to = mail_log.to
        message.from = mail_log.from
        message.cc = mail_log.cc
        message.bcc = mail_log.bcc
        message.reply_to = mail_log.reply_to
        message.return_path = mail_log.return_path
        message.message_id = mail_log.message_id if mail_log.message_id
        message.in_reply_to = mail_log.in_reply_to if mail_log.in_reply_to
        message.references = mail_log.references if mail_log.references
        message.subject = mail_log.subject

        if mail_log.text_plain.present? && mail_log.text_html.present?
          plain_part = ::Mail::Part.new
          plain_part.content_type 'text/plain; charset=UTF-8'
          plain_part.body = mail_log.text_plain
          message.text_part = plain_part

          html_part = ::Mail::Part.new
          html_part.content_type 'text/html; charset=UTF-8'
          html_part.body = mail_log.text_html
          message.html_part = html_part
        elsif mail_log.text_plain.present?
          message.content_type 'text/plain; charset=UTF-8'
          message.body = mail_log.text_plain
        elsif mail_log.text_html.present?
          message.content_type 'text/html; charset=UTF-8'
          message.body = mail_log.text_html
        else
          raise 'message body missing'
        end

        message.header['X-Mailer'] = 'vpsAdmin'
        message.delivery_method(:smtp, smtp_options.merge(return_response: true))
        response = message.deliver!

        {
          provider_message_id: message.message_id,
          response_status: smtp_response_status(response),
          response_body: smtp_response_body(response)
        }
      end

      def deliver_webhook(delivery)
        body = delivery.payload.presence || JSON.dump(Notifications.webhook_payload_for(delivery))
        response = post_json(
          delivery.target_value,
          body,
          webhook_headers(delivery, body),
          delivery
        )

        unless response.code.to_i.between?(200, 299)
          raise WebhookResponseError.new(
            response.code.to_i,
            truncate_body(response.body),
            response_headers(response)
          )
        end

        {
          response_status: response.code.to_i,
          response_body: truncate_body(response.body),
          response_headers: response_headers(response)
        }
      end

      def deliver_telegram(delivery)
        response = telegram_bot.post_json(
          'sendMessage',
          telegram_delivery_payload(delivery)
        )
        body = telegram_response_body(response)

        unless telegram_success?(response, body)
          raise TelegramResponseError.new(
            response.code.to_i,
            truncate_body(response.body),
            telegram_error_summary(response, body)
          )
        end

        {
          provider_message_id: telegram_provider_message_id(body),
          response_status: response.code.to_i,
          response_body: truncate_body(response.body)
        }
      end

      def deliver_sms(delivery)
        payload = sms_delivery_payload(delivery)
        raise 'SMS callback URL is not configured' if payload['callback_url'].blank?

        body = JSON.dump(payload)
        result = Notifications.post_sms_to_gateway!(body, sms: sms_config)

        result.merge(accepted: true)
      end

      def mark_success!(delivery, attempt, result)
        result ||= {}
        now = Time.now

        attempt.update!(
          state: 'succeeded',
          finished_at: now,
          provider_message_id: result[:provider_message_id],
          response_status: result[:response_status],
          response_body: result[:response_body],
          response_headers: result[:response_headers],
          error_summary: nil
        )

        delivery.update!(
          state: 'sent',
          next_attempt_at: nil,
          provider_message_id: result[:provider_message_id],
          response_status: result[:response_status],
          response_body: result[:response_body],
          response_headers: result[:response_headers],
          error_summary: nil
        )
      end

      def mark_accepted!(delivery, attempt, result)
        result ||= {}
        now = Time.now

        delivery.with_lock do
          attempt.update!(
            state: 'succeeded',
            finished_at: now,
            provider_message_id: result[:provider_message_id],
            response_status: result[:response_status],
            response_body: result[:response_body],
            response_headers: result[:response_headers],
            error_summary: nil
          )

          return if delivery.sent_state? || delivery.failed_state?

          delivery.update!(
            state: 'accepted',
            next_attempt_at: nil,
            provider_message_id: result[:provider_message_id],
            response_status: result[:response_status],
            response_body: result[:response_body],
            response_headers: result[:response_headers],
            error_summary: nil
          )
        end
      end

      def mark_failure!(delivery, attempt, response_status:, response_body:, error_summary:, response_headers: nil)
        now = Time.now

        attempt&.update!(
          state: 'failed',
          finished_at: now,
          response_status:,
          response_body:,
          response_headers:,
          error_summary:
        )

        attrs = {
          response_status:,
          response_body:,
          response_headers:,
          error_summary:
        }

        if delivery.attempt_count >= MAX_ATTEMPTS
          attrs[:state] = 'failed'
          attrs[:next_attempt_at] = nil
        else
          attrs[:state] = 'released'
          attrs[:next_attempt_at] = Time.now + backoff_seconds(delivery.attempt_count)
        end

        delivery.update!(attrs)
      end

      def telegram_delivery_payload(delivery)
        payload = JSON.parse(delivery.payload.to_s)
        raise 'Telegram payload is not an object' unless payload.is_a?(Hash)

        ret = {
          chat_id: payload.fetch('chat_id'),
          text: payload.fetch('text')
        }

        ret[:parse_mode] = payload['parse_mode'] if payload['parse_mode'].present?
        ret[:link_preview_options] = payload['link_preview_options'] if payload['link_preview_options'].present?
        ret
      rescue JSON::ParserError
        Notifications.telegram_payload_for(delivery)
      end

      def sms_delivery_payload(delivery)
        payload = JSON.parse(delivery.payload.to_s)
        raise 'SMS payload is not an object' unless payload.is_a?(Hash)

        callback_url = payload['callback_url'].presence || Notifications.sms_callback_url
        raise 'SMS callback URL is not configured' if callback_url.blank?

        payload.merge(
          'to' => payload.fetch('to'),
          'text' => payload.fetch('text'),
          'client_message_id' => delivery.id.to_s,
          'callback_url' => callback_url
        )
      rescue JSON::ParserError
        Notifications.sms_payload_for(delivery)
      end

      def telegram_response_body(response)
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end

      def telegram_success?(response, body)
        response.code.to_i.between?(200, 299) &&
          body.is_a?(Hash) &&
          body.fetch('ok', false)
      end

      def telegram_error_summary(response, body)
        return 'Telegram API returned invalid JSON' if body.nil?
        return 'Telegram API returned non-object JSON' unless body.is_a?(Hash)

        description = body['description']
        return "Telegram API: #{description}" if description.present?
        return "Telegram returned HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

        'Telegram API did not confirm success'
      end

      def telegram_provider_message_id(body)
        result = body['result']
        return unless result.is_a?(Hash)

        result['message_id']&.to_s
      end

      def post_json(url, body, headers, delivery)
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) && uri.host.present?
          raise ArgumentError, 'webhook URL must use HTTP or HTTPS'
        end

        ipaddr = resolve_webhook_address!(uri.host, delivery)

        request = Net::HTTP::Post.new(uri.request_uri, headers)
        request.body = body

        Net::HTTP.start(
          uri.host,
          uri.port,
          ipaddr:,
          use_ssl: uri.scheme == 'https',
          open_timeout: 5,
          read_timeout: 15
        ) do |http|
          http.request(request)
        end
      end

      def webhook_headers(delivery, body)
        headers = {
          'Content-Type' => 'application/json',
          'User-Agent' => 'vpsAdmin notification dispatcher',
          'X-VpsAdmin-Event' => delivery.event.event_type,
          'X-VpsAdmin-Delivery' => delivery.id.to_s
        }

        target = delivery.notification_target || delivery.notification_receiver_action
        if target&.secret.present?
          digest = OpenSSL::HMAC.hexdigest('sha256', target.secret, body)
          headers['X-VpsAdmin-Signature-256'] = "sha256=#{digest}"
        end

        headers
      end

      def resolve_webhook_address!(host, delivery)
        addresses = Resolv.getaddresses(host)
        raise ArgumentError, 'webhook host did not resolve' if addresses.empty?

        addresses.each do |address|
          ip = IPAddr.new(address)
          validate_webhook_destination!(ip, delivery)
        end

        addresses.first
      rescue IPAddr::InvalidAddressError
        raise ArgumentError, 'webhook host did not resolve to an IP address'
      end

      def validate_webhook_destination!(ip, delivery)
        managed_ips = managed_webhook_ip_addresses(ip)
        if managed_ips.any?
          event_user_id = delivery.event&.user_id
          owners = managed_ips.map(&:current_owner)
          return if event_user_id && owners.all? { |owner| owner&.id == event_user_id }

          raise ArgumentError,
                'webhook destination is managed by vpsAdmin and is not owned by the event user'
        end

        return unless private_webhook_address?(ip)
        return if allowed_untracked_private_webhook_address?(ip)

        raise ArgumentError, 'webhook host resolves to a private address'
      end

      def managed_webhook_ip_addresses(ip)
        addr = parse_webhook_ip_address(ip)
        return [] if addr.nil?

        matches = ::IpAddress.where(ip_addr: addr.to_s).to_a

        ::Network.where(ip_version: addr.ipv4? ? 4 : 6).find_each do |net|
          next unless net.include?(addr)

          matches.concat(
            net.ip_addresses.select { |ip_address| ip_address.include?(addr) }
          )
        end

        matches.uniq
      end

      def parse_webhook_ip_address(ip)
        ::IPAddress.parse(ip.to_s)
      rescue ArgumentError
        nil
      end

      def private_webhook_address?(ip)
        PRIVATE_ADDRESS_RANGES.any? { |range| range.include?(ip) }
      end

      def allowed_untracked_private_webhook_address?(ip)
        allowed_untracked_private_webhook_ranges.any? { |range| range.include?(ip) }
      end

      def allowed_untracked_private_webhook_ranges
        @allowed_untracked_private_webhook_ranges ||= Array(
          webhook_config.fetch('allowed_untracked_private_ranges', [])
        ).map { |range| IPAddr.new(range) }
      rescue IPAddr::InvalidAddressError => e
        raise ArgumentError, "invalid webhook allowed untracked private range: #{e.message}"
      end

      def webhook_config
        @config.fetch('webhook', {})
      end

      def telegram_config
        @config.fetch('telegram', {})
      end

      def sms_config
        @config.fetch('sms', {})
      end

      def email_config
        @config.fetch('email', {})
      end

      def smtp_options
        smtp = @config.fetch('smtp', {})
        opts = {
          address: smtp.fetch('address', smtp.fetch('server', 'localhost')),
          port: smtp.fetch('port', 25).to_i,
          openssl_verify_mode: OpenSSL::SSL::VERIFY_NONE,
          open_timeout: smtp.fetch('open_timeout', 30).to_i,
          read_timeout: smtp.fetch('read_timeout', 60).to_i
        }
        opts[:user_name] = smtp['username'] if smtp['username'].present?
        opts[:password] = smtp['password'] if smtp['password'].present?
        opts[:authentication] = smtp['authentication'].to_sym if smtp['authentication'].present?
        unless smtp['enable_starttls_auto'].nil?
          opts[:enable_starttls_auto] = smtp.fetch('enable_starttls_auto')
        end
        opts
      end

      def smtp_response_status(response)
        return unless response.respond_to?(:status)

        status = response.status
        return if status.blank?

        status.to_i
      end

      def smtp_response_body(response)
        return if response.nil?

        body = response.respond_to?(:string) ? response.string : response.to_s
        truncate_body(body)
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

      def exception_response_status(error)
        smtp_response_status(exception_response(error))
      end

      def exception_response_body(error)
        smtp_response_body(exception_response(error))
      end

      def exception_response(error)
        return unless error.respond_to?(:response)

        error.response
      end

      def connection
        @connection ||= Bunny.new(
          hosts: Array(rabbitmq_config.fetch('hosts')),
          vhost: rabbitmq_config.fetch('vhost', '/'),
          username: rabbitmq_config.fetch('username'),
          password: rabbitmq_config.fetch('password'),
          log_file: $stderr
        )
        @connection.start unless @connection.open?
        @connection
      end

      def rabbitmq_configured?
        rabbitmq_config
        true
      rescue KeyError
        false
      end

      def rabbitmq_config
        rabbitmq = @config.fetch('rabbitmq')
        rabbitmq.fetch('hosts')
        rabbitmq.fetch('username')
        rabbitmq.fetch('password')
        rabbitmq
      end

      def poll_interval
        @config.fetch('poll_interval', DEFAULT_POLL_INTERVAL).to_i
      end

      def limit_value
        ENV.fetch('LIMIT', DEFAULT_LIMIT).to_i
      end

      def concurrency
        @concurrency ||= begin
          default =
            case @action
            when 'email'
              DEFAULT_EMAIL_CONCURRENCY
            when 'telegram'
              DEFAULT_TELEGRAM_CONCURRENCY
            when 'sms'
              DEFAULT_SMS_CONCURRENCY
            else
              DEFAULT_WEBHOOK_CONCURRENCY
            end
          positive_integer_config(action_config.fetch('concurrency', default), "#{@action}.concurrency")
        end
      end

      def email_worker_delay
        @email_worker_delay ||= non_negative_float_config(
          email_config.fetch('worker_delay', DEFAULT_EMAIL_WORKER_DELAY),
          'email.worker_delay'
        )
      end

      def email_domain_min_delivery_interval
        @email_domain_min_delivery_interval ||= non_negative_float_config(
          email_config.fetch(
            'domain_min_delivery_interval',
            DEFAULT_EMAIL_DOMAIN_MIN_DELIVERY_INTERVAL
          ),
          'email.domain_min_delivery_interval'
        )
      end

      def action_config
        case @action
        when 'email'
          email_config
        when 'telegram'
          telegram_config
        when 'sms'
          sms_config
        else
          webhook_config
        end
      end

      def positive_integer_config(value, name)
        ret = value.to_i
        raise ArgumentError, "#{name} must be at least 1" if ret < 1

        ret
      end

      def non_negative_float_config(value, name)
        ret = value.to_f
        raise ArgumentError, "#{name} must not be negative" if ret < 0

        ret
      end

      def inline_delivery_dispatch?
        concurrency == 1 || active_database_transaction?
      end

      def active_database_transaction?
        ActiveRecord::Base.connection.transaction_open?
      rescue StandardError
        false
      end

      def backoff_seconds(attempt_count)
        [60 * (2**[attempt_count - 1, 0].max), 3600].min
      end

      def truncate_body(body)
        return if body.nil?

        body.to_s.byteslice(0, RESPONSE_BODY_LIMIT)
      end

      def telegram_bot
        @telegram_bot ||= VpsAdmin::API::TelegramBot.new(config: telegram_config)
      end

      def monotonic_time
        @monotonic_clock.call
      end

      def sleep_seconds(seconds)
        @sleeper.call(seconds)
      end

      def trap_signals
        %w[INT TERM].each do |signal|
          Signal.trap(signal) { @running = false }
        end
      end
    end

    class DomainRateLimiter
      def initialize(interval:, clock:, sleeper:)
        @interval = interval
        @clock = clock
        @sleeper = sleeper
        @next_available_at = {}
        @mutex = Mutex.new
      end

      def wait(domains)
        loop do
          delay = reserve_or_delay(domains)
          return unless delay > 0

          @sleeper.call(delay)
        end
      end

      def delay_for(domains)
        keys = domain_keys(domains)
        return 0 if keys.empty? || @interval <= 0

        @mutex.synchronize do
          delay_for_keys(keys, @clock.call)
        end
      end

      def reserve_or_delay(domains)
        keys = domain_keys(domains)
        return 0 if keys.empty? || @interval <= 0

        @mutex.synchronize do
          now = @clock.call
          delay = delay_for_keys(keys, now)

          if delay <= 0
            reserved_until = now + @interval
            keys.each { |key| @next_available_at[key] = reserved_until }
            return 0
          end

          delay
        end
      end

      protected

      def domain_keys(domains)
        Array(domains).map(&:to_s).reject(&:blank?).uniq.sort
      end

      def delay_for_keys(keys, now)
        available_at = keys.map { |key| @next_available_at.fetch(key, now) }.max
        available_at - now
      end
    end

    class WebhookResponseError < StandardError
      attr_reader :response_status, :response_body, :response_headers

      def initialize(response_status, response_body, response_headers)
        @response_status = response_status
        @response_body = response_body
        @response_headers = response_headers
        super("webhook returned HTTP #{response_status}")
      end
    end

    class TelegramResponseError < StandardError
      attr_reader :response_status, :response_body

      def initialize(response_status, response_body, message)
        @response_status = response_status
        @response_body = response_body
        super(message)
      end
    end

    class SmsGatewayResponseError < StandardError
      attr_reader :response_status, :response_body

      def initialize(response_status, response_body, message)
        @response_status = response_status
        @response_body = response_body
        super(message)
      end
    end
  end
end
