require 'bunny'
require 'ipaddr'
require 'json'
require 'mail'
require 'net/http'
require 'openssl'
require 'resolv'
require 'time'
require 'uri'
require 'yaml'

module VpsAdmin::API
  module Notifications
    EXCHANGE_NAME = 'vpsadmin.notifications'.freeze
    QUEUES = {
      'email' => 'vpsadmin.notifications.email',
      'webhook' => 'vpsadmin.notifications.webhook'
    }.freeze
    ROUTING_KEYS = {
      'email' => 'delivery.email',
      'webhook' => 'delivery.webhook'
    }.freeze
    DEFAULT_LIMIT = 100
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
      receiver_action = delivery.notification_receiver_action
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
          receiver_action: receiver_action && {
            id: receiver_action.id,
            label: receiver_action.label
          }
        }
      }
    end

    def render_email_delivery!(delivery)
      unless delivery.notification_receiver_available?
        delivery.update!(
          state: 'canceled',
          error_summary: 'notification receiver is disabled or muted'
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
          error_summary: 'e-mail template is disabled'
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
                      VpsAdmin::API::Events.email_template_name_for(event)

      if template_name
        return ::MailTemplate.send_mail!(
          template_name,
          VpsAdmin::API::Events.email_template_options_for(event, delivery)
        )
      end

      ::MailTemplate.send_custom(
        VpsAdmin::API::Events.email_custom_options_for(event, delivery)
      )
    end

    def persist_mail_log_snapshot!(mail_log)
      %w[to cc bcc].each do |attr|
        mail_log.public_send("#{attr}=", '') if mail_log.public_send(attr).nil?
      end

      mail_log.save!(validate: false) unless mail_log.persisted?
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

    class Dispatcher
      def self.run(action)
        new(action).run
      end

      def self.dispatch_due(action, **)
        new(action).dispatch_due(**)
      end

      def initialize(action, config: Config.load)
        @action = action.to_s
        raise ArgumentError, "unsupported notification action #{@action}" unless QUEUES.has_key?(@action)

        @config = config
        @running = true
      end

      def run
        trap_signals

        if rabbitmq_configured?
          run_with_rabbitmq
        else
          run_reconciliation_loop
        end
      end

      def dispatch_due(limit: limit_value)
        deliveries = ::EventDelivery
                     .includes(
                       :event,
                       :mail_log,
                       :event_route,
                       :notification_receiver,
                       :notification_receiver_action
                     )
                     .where(action: @action, state: %w[released sending])
                     .due
                     .order(:id)
                     .limit(limit)

        deliveries.each { |delivery| dispatch_delivery(delivery) }
      end

      def dispatch_delivery_id(id)
        return if id.blank?

        delivery = ::EventDelivery
                   .includes(
                     :event,
                     :mail_log,
                     :event_route,
                     :notification_receiver,
                     :notification_receiver_action
                   )
                   .find_by(id:)
        return unless delivery && delivery.action == @action

        dispatch_delivery(delivery)
      end

      protected

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
          ActiveRecord::Base.connection_pool.with_connection do
            dispatch_due
          end

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
        ActiveRecord::Base.connection_pool.with_connection do
          data = JSON.parse(payload)
          dispatch_delivery_id(data['delivery_id'])
        end
        channel.ack(delivery_info.delivery_tag)
      rescue StandardError => e
        warn "Unable to process notification delivery message: #{e.class}: #{e.message}"
        channel.nack(delivery_info.delivery_tag, false, true)
      end

      def run_reconciliation_loop
        while @running
          ActiveRecord::Base.connection_pool.with_connection do
            dispatch_due
          end
          sleep poll_interval
        end
      end

      def dispatch_delivery(delivery)
        attempt = claim_delivery(delivery)
        return unless attempt

        result = deliver(delivery.reload)
        mark_success!(delivery, attempt, result)
      rescue WebhookResponseError => e
        mark_failure!(
          delivery,
          attempt,
          response_status: e.response_status,
          response_body: e.response_body,
          response_headers: e.response_headers,
          error_summary: e.message
        )
      rescue StandardError => e
        mark_failure!(
          delivery,
          attempt,
          response_status: exception_response_status(e),
          response_body: exception_response_body(e),
          error_summary: "#{e.class}: #{e.message}"
        )
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

          unless delivery.receiver_action_available?
            delivery.update!(
              state: 'canceled',
              error_summary: "#{@action} action is not available"
            )
            next
          end

          attempt_number = delivery.attempt_count + 1
          mark_stale_attempts_failed!(delivery) if delivery.sending_state?

          attempt = delivery.event_delivery_attempts.create!(
            action: delivery.action,
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
        case @action
        when 'email'
          deliver_email(delivery)
        when 'webhook'
          deliver_webhook(delivery)
        else
          raise ArgumentError, "unsupported notification action #{@action}"
        end
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
          webhook_headers(delivery, body)
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

      def post_json(url, body, headers)
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) && uri.host.present?
          raise ArgumentError, 'webhook URL must use HTTP or HTTPS'
        end

        ipaddr = resolve_public_webhook_address!(uri.host)

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

        action = delivery.notification_receiver_action
        if action&.secret.present?
          digest = OpenSSL::HMAC.hexdigest('sha256', action.secret, body)
          headers['X-VpsAdmin-Signature-256'] = "sha256=#{digest}"
        end

        headers
      end

      def resolve_public_webhook_address!(host)
        addresses = Resolv.getaddresses(host)
        raise ArgumentError, 'webhook host did not resolve' if addresses.empty?

        addresses.each do |address|
          ip = IPAddr.new(address)
          next unless private_webhook_address?(ip)
          next if allowed_private_webhook_address?(ip)

          raise ArgumentError, 'webhook host resolves to a private address'
        end

        addresses.first
      rescue IPAddr::InvalidAddressError
        raise ArgumentError, 'webhook host did not resolve to an IP address'
      end

      def private_webhook_address?(ip)
        PRIVATE_ADDRESS_RANGES.any? { |range| range.include?(ip) }
      end

      def allowed_private_webhook_address?(ip)
        allowed_private_webhook_ranges.any? { |range| range.include?(ip) }
      end

      def allowed_private_webhook_ranges
        @allowed_private_webhook_ranges ||= Array(
          webhook_config.fetch('allowed_private_ranges', [])
        ).map { |range| IPAddr.new(range) }
      rescue IPAddr::InvalidAddressError => e
        raise ArgumentError, "invalid webhook allowed private range: #{e.message}"
      end

      def webhook_config
        @config.fetch('webhook', {})
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

      def backoff_seconds(attempt_count)
        [60 * (2**[attempt_count - 1, 0].max), 3600].min
      end

      def truncate_body(body)
        return if body.nil?

        body.to_s.byteslice(0, RESPONSE_BODY_LIMIT)
      end

      def trap_signals
        %w[INT TERM].each do |signal|
          Signal.trap(signal) { @running = false }
        end
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
  end
end
