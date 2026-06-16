require 'json'
require 'ipaddr'
require 'net/http'
require 'openssl'
require 'resolv'
require 'uri'

module VpsAdmin::API::Tasks
  class EventDelivery < Base
    DEFAULT_LIMIT = 100
    MAX_ATTEMPTS = 5
    TRANSACTION_SUCCESS = 1
    RESPONSE_BODY_LIMIT = 8192
    WEBHOOK_CLAIM_TIMEOUT = 5 * 60
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

    def deliver_emails
      queue_email_deliveries
      sync_email_deliveries
    end

    def deliver_webhooks
      deliveries = ::EventDelivery
                   .includes(
                     :event,
                     :event_route,
                     :notification_receiver,
                     :notification_receiver_action
                   )
                   .where(action: 'webhook', state: %w[planned queued])
                   .where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.now)
                   .order(:id)
                   .limit(limit)

      deliveries.each { |delivery| deliver_webhook(delivery) }
    end

    protected

    def queue_email_deliveries
      deliveries = ::EventDelivery
                   .includes(
                     :event,
                     :notification_receiver,
                     :notification_receiver_action
                   )
                   .where(action: 'email', state: %w[planned queued])
                   .where(transaction_id: nil)
                   .where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.now)
                   .order(:id)
                   .limit(limit)

      deliveries.each do |delivery|
        TransactionChains::EventDelivery::Email.fire2(args: [delivery])
      end
    end

    def sync_email_deliveries
      deliveries = ::EventDelivery
                   .includes(delivery_transaction: :transaction_chain)
                   .where(action: 'email', state: 'queued')
                   .where.not(transaction_id: nil)
                   .order(:id)
                   .limit(limit)

      deliveries.each { |delivery| sync_email_delivery(delivery) }
    end

    def sync_email_delivery(delivery)
      transaction = delivery.delivery_transaction
      chain = transaction&.transaction_chain
      return unless transaction && chain

      if transaction.done? && transaction.status == TRANSACTION_SUCCESS
        delivery.update!(
          state: 'sent',
          error_summary: nil
        )
      elsif transaction.done?
        delivery.update!(
          state: 'failed',
          error_summary: "mail transaction failed with status #{transaction.status}"
        )
      elsif chain.failed? || chain.fatal? || chain.resolved?
        delivery.update!(
          state: 'failed',
          error_summary: "mail transaction chain is #{chain.state}"
        )
      end
    end

    def deliver_webhook(delivery)
      action = delivery.notification_receiver_action

      unless delivery.notification_receiver_available?
        delivery.update!(
          state: 'canceled',
          error_summary: 'notification receiver is disabled or muted'
        )
        return
      end

      unless action&.webhook_action? && action.enabled?
        delivery.update!(
          state: 'canceled',
          error_summary: 'webhook action is not available'
        )
        return
      end

      return unless claim_webhook_delivery(delivery)

      body = JSON.dump(payload_for(delivery))
      response = post_json(delivery.target_value, body, headers_for(delivery, action, body))

      if response.code.to_i.between?(200, 299)
        delivery.update!(
          state: 'sent',
          next_attempt_at: nil,
          response_status: response.code.to_i,
          response_body: truncate_body(response.body),
          error_summary: nil
        )
      else
        retry_or_fail!(
          delivery,
          response_status: response.code.to_i,
          response_body: truncate_body(response.body),
          error_summary: "webhook returned HTTP #{response.code}"
        )
      end
    rescue StandardError => e
      retry_or_fail!(
        delivery,
        response_status: nil,
        response_body: nil,
        error_summary: "#{e.class}: #{e.message}"
      )
    end

    def claim_webhook_delivery(delivery)
      delivery.with_lock do
        next false unless delivery.webhook_action?
        next false unless delivery_due?(delivery)

        delivery.update!(
          state: 'queued',
          attempt_count: delivery.attempt_count + 1,
          last_attempt_at: Time.now,
          next_attempt_at: Time.now + WEBHOOK_CLAIM_TIMEOUT
        )

        true
      end
    end

    def delivery_due?(delivery)
      return true if delivery.planned_state?
      return false unless delivery.queued_state?

      delivery.next_attempt_at.nil? || delivery.next_attempt_at <= Time.now
    end

    def post_json(url, body, headers)
      uri = URI.parse(url)
      raise ArgumentError, 'webhook URL must use HTTP or HTTPS' unless uri.is_a?(URI::HTTP) && uri.host.present?

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

    def resolve_public_webhook_address!(host)
      addresses = Resolv.getaddresses(host)
      raise ArgumentError, 'webhook host did not resolve' if addresses.empty?

      addresses.each do |address|
        ip = IPAddr.new(address)
        next if ENV['VPSADMIN_EVENT_WEBHOOK_ALLOW_PRIVATE'] == '1'
        next unless private_webhook_address?(ip)

        raise ArgumentError, 'webhook host resolves to a private address'
      end

      addresses.first
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, 'webhook host did not resolve to an IP address'
    end

    def private_webhook_address?(ip)
      PRIVATE_ADDRESS_RANGES.any? { |range| range.include?(ip) }
    end

    def headers_for(delivery, action, body)
      headers = {
        'Content-Type' => 'application/json',
        'User-Agent' => 'vpsAdmin event delivery',
        'X-Vpsadmin-Event' => delivery.event.event_type,
        'X-Vpsadmin-Delivery' => delivery.id.to_s
      }

      if action.secret.present?
        digest = OpenSSL::HMAC.hexdigest('sha256', action.secret, body)
        headers['X-Hub-Signature-256'] = "sha256=#{digest}"
      end

      headers
    end

    def payload_for(delivery)
      event = delivery.event
      route = delivery.event_route
      receiver = delivery.notification_receiver
      action = delivery.notification_receiver_action
      vps = event.vps
      user = event.user

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
          receiver_action: action && {
            id: action.id,
            label: action.label
          }
        }
      }
    end

    def retry_or_fail!(delivery, response_status:, response_body:, error_summary:)
      attrs = {
        response_status:,
        response_body:,
        error_summary:
      }

      if delivery.attempt_count >= MAX_ATTEMPTS
        attrs[:state] = 'failed'
      else
        attrs[:state] = 'queued'
        attrs[:next_attempt_at] = Time.now + backoff_seconds(delivery.attempt_count)
      end

      delivery.update!(attrs)
    end

    def backoff_seconds(attempt_count)
      [60 * (2**[attempt_count - 1, 0].max), 3600].min
    end

    def truncate_body(body)
      return if body.nil?

      body.to_s.byteslice(0, RESPONSE_BODY_LIMIT)
    end

    def limit
      ENV.fetch('LIMIT', DEFAULT_LIMIT).to_i
    end
  end
end
