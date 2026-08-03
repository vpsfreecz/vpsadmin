require 'digest'
require 'net/http'
require 'openssl'
require 'securerandom'
require 'time'
require 'uri'

module VpsAdmin::API::Notifications::DeliveryActions
  class Sms < Base
    class GatewayResponseError < VpsAdmin::API::Notifications::DeliveryFailure
      def initialize(response_status, response_body, message)
        super(message, response_status:, response_body:)
      end
    end

    class CallbackAuthenticationError < StandardError; end
    class CallbackConflictError < StandardError; end

    DEFAULT_CONCURRENCY = 1
    TEXT_LIMIT = 459
    CALLBACK_PATH = '/internal/notifications/sms/callback'.freeze
    CALLBACK_MAX_BODY_SIZE = 16 * 1024
    CALLBACK_SIGNATURE_VERSION = 'v1'.freeze
    CALLBACK_SIGNATURE_TOLERANCE = 20 * 60
    VERIFICATION_CLIENT_ID_PREFIX = 'verification-action-'.freeze

    action :sms,
           label: 'SMS',
           queue: 'vpsadmin.notifications.sms',
           routing_key: 'delivery.sms',
           default_concurrency: DEFAULT_CONCURRENCY,
           default_rate_limits: {
             minute: 3,
             hour: 30,
             day: 150,
             week: 300
           },
           template_context_fallbacks: [:email],
           templates: true
    target_kind :custom, label: 'custom target'

    def available?
      sms = action_config
      return false if sms.has_key?('enabled') && !truthy_config?(sms['enabled'])

      truthy_config?(sms.fetch('configured', false)) || gateways(sms).any?
    rescue KeyError
      false
    end

    def validate_target(target)
      unless target.custom_target_kind?
        target.errors.add(:target_kind, 'must be custom')
        return
      end

      if target.target_value.blank?
        target.errors.add(:target_value, "can't be blank")
        return
      end

      return if target.target_value.match?(::NotificationTarget::SMS_PHONE_FORMAT)

      target.errors.add(:target_value, 'must be an E.164 phone number, e.g. +420123456789')
    end

    def normalize_target_value(_target_kind, value)
      ::NotificationTarget.normalize_sms_target(value)
    end

    def identity_key(target_kind:, target_value:, secret: nil)
      normalize_target_value(target_kind, target_value)
    end

    def display_target(target)
      target.target_value.presence || 'Phone number'
    end

    def target_available?(target)
      target.verified? && target.target_value.present?
    end

    def admin_verification_skippable?(_target)
      true
    end

    def plan_delivery(context:, route:, receiver:, receiver_action:)
      if receiver_action.target_value.blank?
        return context.skip(route, receiver, receiver_action, 'SMS number is not configured')
      end
      unless receiver_action.verified?
        return context.skip(route, receiver, receiver_action, 'SMS number is not verified')
      end

      context.build(
        route,
        receiver,
        receiver_action,
        target_value: receiver_action.target_value,
        target_label: receiver_action.display_target
      )
    end

    def prepare_delivery(delivery)
      return unless delivery.payload.blank?

      delivery.update!(payload: JSON.dump(payload_for(delivery)))
    end

    def deliver(delivery)
      payload = delivery_payload(delivery)
      raise 'SMS callback URL is not configured' if payload['callback_url'].blank?

      result = post_to_gateway!(JSON.dump(payload))

      VpsAdmin::API::Notifications::DeliveryResult.new(
        outcome: :accepted,
        provider_message_id: result[:provider_message_id],
        response_status: result[:response_status],
        response_body: result[:response_body],
        response_headers: result[:response_headers]
      )
    end

    def payload_for(delivery)
      {
        to: delivery.target_value,
        text: text_for(delivery),
        client_message_id: delivery.id.to_s,
        callback_url:,
        callback_secret: callback_secret
      }
    end

    def send_verification!(target)
      target.ensure_sms_verification_code!
      body = JSON.dump({
                         to: target.target_value,
                         text: verification_text(target),
                         client_message_id: "#{VERIFICATION_CLIENT_ID_PREFIX}#{target.id}"
                       })
      post_to_gateway!(body)
      target.mark_sms_verification_sent!
    end

    def callback_secret
      SecureRandom.hex(32)
    end

    def callback_url
      configured = action_config['callback_url'].presence
      return configured if configured

      api_url = ::SysConfig.get(:core, :api_url).to_s.chomp('/')
      return if api_url.blank?

      "#{api_url}#{CALLBACK_PATH}"
    rescue StandardError
      nil
    end

    def apply_gateway_callback!(payload, raw_body: nil, headers: {}, authorization: nil,
                                request_method: 'POST',
                                request_path: CALLBACK_PATH,
                                now: Time.now)
      payload = payload.to_h
      client_message_id = payload.fetch('client_message_id').to_s
      unless client_message_id.match?(/\A[0-9]+\z/)
        raise CallbackAuthenticationError,
              'Invalid SMS callback authorization'
      end

      delivery = ::EventDelivery.find_by(id: client_message_id)
      unless delivery&.sms_action?
        raise CallbackAuthenticationError,
              'Invalid SMS callback authorization'
      end

      verify_gateway_callback!(
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
            raise CallbackConflictError,
                  'SMS delivery already has a different final state'
          end

          return delivery
        end

        current_time = Time.now
        attrs = {
          response_status: 200,
          response_body: truncate_response_body(JSON.dump(payload)),
          provider_message_id: callback_provider_message_id(payload) || delivery.provider_message_id,
          last_attempt_at: current_time,
          updated_at: current_time
        }

        case status
        when 'sent'
          attrs[:state] = 'sent'
          attrs[:next_attempt_at] = nil
          attrs[:error_summary] = nil
        when 'failed'
          attrs[:state] = 'failed'
          attrs[:next_attempt_at] = nil
          attrs[:error_summary] = payload['error_summary'].presence ||
                                  'SMS gateway reported final failure'
        else
          raise ArgumentError, "unsupported SMS status #{status.inspect}"
        end

        delivery.update!(attrs)
      end
      delivery
    end

    def post_to_gateway!(body, sms: action_config)
      configured_gateways = gateways(sms)
      if configured_gateways.empty?
        raise GatewayResponseError.new(
          nil,
          nil,
          'SMS gateways are not configured'
        )
      end

      last_error = nil
      configured_gateways.each do |gateway|
        response = post_gateway_request(gateway, body, sms:)
        if response.code.to_i.between?(200, 299)
          return gateway_success(gateway, response)
        end

        last_error = GatewayResponseError.new(
          response.code.to_i,
          truncate_response_body(response.body),
          "SMS gateway #{gateway.fetch('name')} returned HTTP #{response.code}"
        )
      rescue StandardError => e
        last_error = GatewayResponseError.new(
          nil,
          nil,
          "SMS gateway #{gateway.fetch('name')} failed: #{e.message}"
        )
      end

      raise last_error || GatewayResponseError.new(
        nil,
        nil,
        'SMS gateways are not configured'
      )
    end

    protected

    def text_for(delivery)
      return grouped_text_for(delivery) if generic_group_rendering?(delivery)

      event = delivery.event
      template_name = template_name_for_delivery(delivery)

      if template_name
        rendered = ::NotificationTemplate.render_sms!(
          template_name,
          VpsAdmin::API::Events.template_options_for(event, delivery, action: :sms)
        )
        return truncate_text(rendered.fetch(:text))
      end

      lines = [
        "[#{event.severity}] #{event.subject}",
        "Event: #{event.event_type}"
      ]
      lines << "VPS: ##{event.vps.id} #{event.vps.hostname}" if event.vps

      truncate_text(lines.join("\n"))
    end

    def grouped_text_for(delivery)
      if grouped_template_available?(delivery)
        rendered = ::NotificationTemplate.render_sms!(
          :event_group,
          grouped_template_options_for(delivery, event_limit: 10)
        )
        return truncate_text(rendered.fetch(:text))
      end

      events = delivery.group_events.limit(10).to_a
      lines = ["#{delivery.event_count} grouped vpsAdmin notifications"]
      lines.concat(events.map { |event| "[#{event.severity}] #{event.subject}" })
      truncate_text(lines.join("\n"))
    end

    def truncate_text(text)
      text.to_s[0, TEXT_LIMIT]
    end

    def verification_text(target)
      template = action_config.fetch(
        'verification_text',
        'Your vpsAdmin verification code is %{code}'
      )
      format(template, code: target.verification_credential)
    end

    def delivery_payload(delivery)
      payload = JSON.parse(delivery.payload.to_s)
      raise 'SMS payload is not an object' unless payload.is_a?(Hash)

      delivery_callback_url = payload['callback_url'].presence || callback_url
      raise 'SMS callback URL is not configured' if delivery_callback_url.blank?

      payload.merge(
        'to' => payload.fetch('to'),
        'text' => payload.fetch('text'),
        'client_message_id' => delivery.id.to_s,
        'callback_url' => delivery_callback_url
      )
    rescue JSON::ParserError
      payload_for(delivery)
    end

    def verify_gateway_callback!(delivery, raw_body, headers:, authorization:, request_method:,
                                 request_path:, now:)
      secret = callback_secret_for_delivery(delivery)
      if secret.present?
        verify_gateway_callback_hmac!(
          secret,
          raw_body,
          headers:,
          request_method:,
          request_path:,
          now:
        )
      else
        verify_legacy_gateway_callback!(authorization)
      end
    end

    def verify_legacy_gateway_callback!(authorization)
      token = callback_token
      if token.present? && secure_compare(authorization.to_s, "Bearer #{token}")
        return
      end

      raise CallbackAuthenticationError,
            'Invalid SMS callback authorization'
    end

    def verify_gateway_callback_hmac!(secret, raw_body, headers:, request_method:,
                                      request_path:, now:)
      version = callback_header(headers, 'X-VpsAdmin-SMS-Signature-Version').to_s
      timestamp_raw = callback_header(headers, 'X-VpsAdmin-SMS-Timestamp').to_s
      signature = callback_header(headers, 'X-VpsAdmin-SMS-Signature').to_s

      unless version == CALLBACK_SIGNATURE_VERSION
        raise CallbackAuthenticationError,
              'Invalid SMS callback signature version'
      end

      timestamp = Time.iso8601(timestamp_raw)
      if timestamp < now - CALLBACK_SIGNATURE_TOLERANCE ||
         timestamp > now + CALLBACK_SIGNATURE_TOLERANCE
        raise CallbackAuthenticationError,
              'Stale SMS callback timestamp'
      end

      body_hash = Digest::SHA256.hexdigest(raw_body.to_s)
      signature_input = [
        CALLBACK_SIGNATURE_VERSION,
        request_method.to_s.upcase,
        request_path.presence || '/',
        timestamp_raw,
        body_hash
      ].join("\n")
      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, signature_input)}"
      unless secure_compare(signature, expected)
        raise CallbackAuthenticationError,
              'Invalid SMS callback signature'
      end
    rescue ArgumentError
      raise CallbackAuthenticationError,
            'Invalid SMS callback timestamp'
    end

    def callback_header(headers, name)
      headers[name] ||
        headers[name.downcase] ||
        headers["HTTP_#{name.upcase.tr('-', '_')}"]
    end

    def callback_secret_for_delivery(delivery)
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

    def callback_provider_message_id(payload)
      gateway = payload['gateway'].presence
      provider_id = payload['provider_id'].presence ||
                    payload['gateway_message_id'].presence
      [gateway, provider_id].compact.join(':').presence
    end

    def truncate_response_body(body)
      return if body.nil?

      body.to_s.byteslice(0, VpsAdmin::API::Notifications::RESPONSE_BODY_LIMIT).to_s.scrub
    end

    def post_gateway_request(gateway, body, sms: action_config)
      uri = URI.parse(gateway.fetch('url'))
      unless uri.is_a?(URI::HTTP) && uri.host.present?
        raise ArgumentError, 'SMS gateway URL must use HTTP or HTTPS'
      end

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{gateway.fetch('token')}"
      request.body = body

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout: sms.fetch('open_timeout', 5).to_i,
        read_timeout: sms.fetch('read_timeout', 15).to_i
      ) do |http|
        http.request(request)
      end
    end

    def gateway_success(gateway, response)
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

    def gateways(sms = action_config)
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

    def callback_token
      action_config['callback_token'].presence ||
        ENV['VPSADMIN_SMS_CALLBACK_TOKEN'].presence
    end
  end

  register Sms
end
