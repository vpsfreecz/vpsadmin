require 'digest'
require 'ipaddr'
require 'net/http'
require 'openssl'
require 'resolv'

module VpsAdmin::API::Notifications::DeliveryActions
  class Webhook < Base
    class ResponseError < StandardError
      attr_reader :response_status, :response_body, :response_headers

      def initialize(response_status, response_body, response_headers)
        @response_status = response_status
        @response_body = response_body
        @response_headers = response_headers
        super("webhook returned HTTP #{response_status}")
      end
    end

    DEFAULT_CONCURRENCY = 4
    EVENT_LIMIT = 100
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

    action :webhook,
           label: 'Webhook',
           queue: 'vpsadmin.notifications.webhook',
           routing_key: 'delivery.webhook',
           default_concurrency: DEFAULT_CONCURRENCY,
           default_rate_limits: {
             minute: 60,
             hour: 1000,
             day: 10_000,
             week: 25_000
           }
    target_kind :custom, label: 'custom target'

    def validate_target(target)
      if target.target_value.blank?
        target.errors.add(:target_value, "can't be blank")
        return
      end

      uri = URI.parse(target.target_value)
      return if uri.is_a?(URI::HTTP) && uri.host.present?

      target.errors.add(:target_value, 'must be an HTTP or HTTPS URL')
    rescue URI::InvalidURIError
      target.errors.add(:target_value, 'must be an HTTP or HTTPS URL')
    end

    def identity_key(target_kind:, target_value:, secret: nil)
      url = target_value.to_s.strip
      return if url.blank?

      "url:#{Digest::SHA256.hexdigest("#{url}\0#{secret}")}"
    end

    def display_target(target)
      target.target_value.presence || 'Webhook URL'
    end

    def target_available?(target)
      target.target_value.present?
    end

    def plan_delivery(context:, route:, receiver:, receiver_action:)
      if receiver_action.target_value.blank?
        return context.skip(route, receiver, receiver_action, 'webhook URL is not configured')
      end

      context.build(
        route,
        receiver,
        receiver_action,
        target_value: receiver_action.target_value,
        target_label: receiver_action.label
      )
    end

    def prepare_delivery(delivery)
      return unless delivery.payload.blank?

      delivery.update!(
        payload: JSON.dump(payload_for(delivery))
      )
    end

    def deliver(delivery)
      body = delivery.payload.presence ||
             JSON.dump(payload_for(delivery))
      response = post_json(
        delivery.target_value,
        body,
        headers(delivery, body),
        delivery
      )

      unless response.code.to_i.between?(200, 299)
        raise ResponseError.new(
          response.code.to_i,
          truncate_body(response.body),
          response_headers(response)
        )
      end

      VpsAdmin::API::Notifications::DeliveryResult.new(
        response_status: response.code.to_i,
        response_body: truncate_body(response.body),
        response_headers: response_headers(response)
      )
    end

    def payload_for(delivery)
      members = delivery
                .group_members
                .includes(event: %i[user vps])
                .limit(EVENT_LIMIT)
                .to_a
      events = members.map do |member|
        event_for(member.event, route_context: member.event_routing_context)
      end
      event_count = delivery.event_count
      route = delivery.event_route
      receiver = delivery.notification_receiver
      target = delivery.notification_target
      receiver_target = delivery.notification_receiver_target ||
                        delivery.notification_receiver_action

      {
        version: 1,
        group: {
          grouped: delivery.event_delivery_group_id.present?,
          key: delivery.event_delivery_group&.group_key,
          labels: delivery.event_delivery_group&.labels || {},
          event_count:,
          truncated_count: [event_count - events.length, 0].max
        },
        events:,
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

    def event_for(event, route_context:)
      user = event.user
      vps = event.vps

      {
        id: event.id,
        type: event.event_type,
        category: event.category,
        severity: event.severity,
        subject: event.subject,
        summary: event.summary,
        payload: event.payload || {},
        fields: VpsAdmin::API::Events.matchable_field_values(event, route_context:),
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
      }
    end

    def headers(delivery, body)
      ret = {
        'Content-Type' => 'application/json',
        'User-Agent' => 'vpsAdmin notification dispatcher',
        'X-VpsAdmin-Delivery' => delivery.id.to_s
      }
      ret['X-VpsAdmin-Event'] = delivery.event.event_type if delivery.event_count == 1
      if delivery.event_delivery_group
        ret['X-VpsAdmin-Group'] = delivery.event_delivery_group.group_key
      end

      if delivery.target_secret.present?
        digest = OpenSSL::HMAC.hexdigest('sha256', delivery.target_secret, body)
        ret['X-VpsAdmin-Signature-256'] = "sha256=#{digest}"
      end

      ret
    end

    protected

    def post_json(url, body, request_headers, delivery)
      uri = URI.parse(url)
      unless uri.is_a?(URI::HTTP) && uri.host.present?
        raise ArgumentError, 'webhook URL must use HTTP or HTTPS'
      end

      ipaddr = resolve_address!(uri.host, delivery)
      request = Net::HTTP::Post.new(uri.request_uri, request_headers)
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

    def resolve_address!(host, delivery)
      addresses = Resolv.getaddresses(host)
      raise ArgumentError, 'webhook host did not resolve' if addresses.empty?

      addresses.each do |address|
        validate_destination!(IPAddr.new(address), delivery)
      end

      addresses.first
    rescue IPAddr::InvalidAddressError
      raise ArgumentError, 'webhook host did not resolve to an IP address'
    end

    def validate_destination!(ip, delivery)
      managed_ips = managed_ip_addresses(ip)
      if managed_ips.any?
        event_user_ids = delivery.group_events.distinct.pluck(:user_id)
        owners = managed_ips.map(&:current_owner)
        if event_user_ids.one? && event_user_ids.first &&
           owners.all? { |owner| owner&.id == event_user_ids.first }
          return
        end

        raise ArgumentError,
              'webhook destination is managed by vpsAdmin and is not owned by the event user'
      end

      return unless private_address?(ip)
      return if allowed_untracked_private_address?(ip)

      raise ArgumentError, 'webhook host resolves to a private address'
    end

    def managed_ip_addresses(ip)
      addr = parse_ip_address(ip)
      return [] if addr.nil?

      matches = ::IpAddress.where(ip_addr: addr.to_s).to_a
      ::Network.where(ip_version: addr.ipv4? ? 4 : 6).find_each do |net|
        next unless net.include?(addr)

        matches.concat(net.ip_addresses.select { |ip_address| ip_address.include?(addr) })
      end
      matches.uniq
    end

    def parse_ip_address(ip)
      ::IPAddress.parse(ip.to_s)
    rescue ArgumentError
      nil
    end

    def private_address?(ip)
      PRIVATE_ADDRESS_RANGES.any? { |range| range.include?(ip) }
    end

    def allowed_untracked_private_address?(ip)
      allowed_untracked_private_ranges.any? { |range| range.include?(ip) }
    end

    def allowed_untracked_private_ranges
      @allowed_untracked_private_ranges ||= Array(
        action_config.fetch('allowed_untracked_private_ranges', [])
      ).map { |range| IPAddr.new(range) }
    rescue IPAddr::InvalidAddressError => e
      raise ArgumentError, "invalid webhook allowed untracked private range: #{e.message}"
    end
  end

  register Webhook
end
