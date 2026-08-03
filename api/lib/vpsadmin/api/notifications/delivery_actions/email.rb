require 'digest'
require 'mail'
require 'openssl'
require 'uri'

module VpsAdmin::API::Notifications::DeliveryActions
  class Email < Base
    class VerificationDeliveryError < StandardError; end

    DEFAULT_CONCURRENCY = 2
    DEFAULT_WORKER_DELAY = 1.0
    DEFAULT_DOMAIN_MIN_DELIVERY_INTERVAL = 1.0
    DUE_SCAN_MULTIPLIER = 4

    action :email,
           label: 'E-mail',
           queue: 'vpsadmin.notifications.email',
           routing_key: 'delivery.email',
           default_concurrency: DEFAULT_CONCURRENCY,
           default_rate_limits: {
             minute: 30,
             hour: 300,
             day: 2000,
             week: 5000
           },
           templates: true
    target_kind :default_recipient, label: 'default recipient'
    target_kind :custom, label: 'custom target'

    def validate_target(target)
      return if target.default_recipient_target_kind?

      if target.target_value.blank?
        target.errors.add(:target_value, "can't be blank")
        return
      end

      if target.target_value.length > ::NotificationTarget::MAIL_TARGET_VALUE_LIMIT
        target.errors.add(
          :target_value,
          "is too long (maximum is #{::NotificationTarget::MAIL_TARGET_VALUE_LIMIT} characters)"
        )
        return
      end

      addresses = ::NotificationTarget.parsed_email_target_addresses(target.target_value)
      if addresses.nil? || addresses.empty?
        target.errors.add(:target_value, "'#{target.target_value}' is not a valid e-mail address")
        return
      end

      unless addresses.one?
        target.errors.add(:target_value, 'must contain one e-mail address')
        return
      end

      return if ::NotificationTarget.valid_email_target_address?(addresses.first)

      target.errors.add(:target_value, "'#{target.target_value}' is not a valid e-mail address")
    end

    def normalize_target_value(target_kind, value)
      return value unless target_kind.to_s == 'custom'

      ::NotificationTarget.normalize_email_target(value)
    end

    def identity_key(target_kind:, target_value:, secret: nil)
      if target_kind.to_s == 'default_recipient'
        'default'
      elsif (target = normalize_target_value(target_kind, target_value))
        "custom:#{Digest::SHA256.hexdigest(target)}"
      end
    end

    def display_target(target)
      target.target_value.presence || 'Account e-mail'
    end

    def target_available?(target)
      !verification_required?(target) || target.verified?
    end

    def default_target_kind
      'default_recipient'
    end

    def verification_required?(target)
      target.custom_target_kind?
    end

    def admin_verification_skippable?(target)
      verification_required?(target)
    end

    def plan_delivery(context:, route:, receiver:, receiver_action:)
      if verification_required?(receiver_action) && !receiver_action.verified?
        return context.skip(route, receiver, receiver_action, 'e-mail target is not verified')
      end

      if receiver_action.default_recipient_target_kind?
        if context.route_context&.route_owner.nil?
          return context.skip(route, receiver, receiver_action, 'route has no recipient user')
        end

        target = if context.route_context&.self_subject?
                   VpsAdmin::API::Events.default_email_target_for(
                     context.event,
                     route_context: context.route_context
                   )
                 end
        return context.build(
          route,
          receiver,
          receiver_action,
          target_value: target.presence || 'default',
          target_label: target.present? ? target : 'Default recipient'
        )
      end

      context.build(
        route,
        receiver,
        receiver_action,
        target_value: receiver_action.target_value,
        target_label: context.label(receiver_action.target_value)
      )
    end

    def direct_delivery_plans(context:)
      return [] unless context.event.user_id.blank?

      custom_target = VpsAdmin::API::Events.custom_email_target_for(context.event).presence
      if custom_target
        return [context.direct(
          action: name,
          target_kind: 'custom',
          target_value: custom_target,
          target_label: custom_target
        )]
      end

      default_target = VpsAdmin::API::Events.default_email_target_for(context.event).presence
      return [] unless default_target

      [context.direct(
        action: name,
        target_kind: 'default_recipient',
        target_value: default_target,
        target_label: default_target,
        template_name: VpsAdmin::API::Events.template_name_for(context.event, name)
      )]
    end

    def prepare_delivery(delivery)
      render_delivery!(delivery, strict: delivery.sending_state?)
    end

    def prepared?(delivery)
      delivery.mail_log_id.present?
    end

    def deliver(delivery)
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

      set_message_body(message, mail_log)
      message.header['X-Mailer'] = 'vpsAdmin'
      message.delivery_method(:smtp, smtp_options.merge(return_response: true))
      response = message.deliver!

      VpsAdmin::API::Notifications::DeliveryResult.new(
        provider_message_id: message.message_id,
        response_status: smtp_response_status(response),
        response_body: smtp_response_body(response)
      )
    end

    def send_verification!(target)
      target.ensure_email_verification_token!
      mail_log = ::NotificationTemplate.send_custom_email(
        user: target.user,
        from: VpsAdmin::API::NotificationTemplateReconciler.default_from,
        to: [target.target_value],
        subject: 'Verify your vpsAdmin notification e-mail target',
        text_plain: verification_text(target)
      )
      deliver_mail_log!(mail_log)
      target.mark_email_verification_sent!
      target.update!(last_error: nil)
      mail_log
    rescue StandardError => e
      target&.update(last_error: e.message) if target&.persisted?
      raise VerificationDeliveryError, e.message
    end

    def deliver_mail_log!(mail_log)
      delivery = Struct.new(:mail_log).new(mail_log)
      deliver(delivery)
    end

    def render_delivery!(delivery, strict: false)
      unless delivery.notification_receiver_available?
        raise VpsAdmin::API::Notifications::DeliveryPreparationTerminalError.new(
          'canceled',
          'notification receiver is disabled or muted'
        )
      end

      unless delivery.delivery_method_enabled?
        raise VpsAdmin::API::Notifications::DeliveryPreparationTerminalError.new(
          'canceled',
          'email delivery method is disabled'
        )
      end

      unless delivery.receiver_action_available?
        raise VpsAdmin::API::Notifications::DeliveryPreparationTerminalError.new(
          'canceled',
          'e-mail action is not available'
        )
      end

      mail_log = build_mail_log(delivery)

      if mail_log.nil?
        raise VpsAdmin::API::Notifications::DeliveryPreparationTerminalError.new(
          'skipped',
          'notification template is disabled'
        )
      end

      persist_mail_log_snapshot!(mail_log)

      delivery.update!(
        mail_log:,
        error_summary: nil
      )
    rescue VpsAdmin::API::Notifications::DeliveryPreparationTerminalError => e
      raise if strict

      delivery.update!(
        state: e.delivery_state,
        error_summary: e.message
      )
    rescue StandardError => e
      raise if strict

      delivery.update!(
        state: 'failed',
        error_summary: "#{e.class}: #{e.message}"
      )
    end

    def select_due_deliveries(limit:, scan_limit:, due_scope:)
      return super if domain_min_delivery_interval <= 0

      limit = limit.to_i
      scan_limit = [scan_limit.to_i, limit].max
      max_scan = scan_limit * DUE_SCAN_MULTIPLIER
      selected = []
      overflow = []
      seen_domains = Set.new
      last_id = nil
      scanned = 0

      loop do
        batch_limit = [scan_limit, max_scan - scanned].min
        break if batch_limit <= 0

        scope = due_scope.call
        scope = scope.where('event_deliveries.id > ?', last_id) if last_id
        batch = scope.limit(batch_limit).to_a
        break if batch.empty?

        scanned += batch.size
        batch.each do |delivery|
          last_id = delivery.id
          domains = recipient_domains(delivery)

          if domain_limiter.delay_for(domains) <= 0 && domains.any? { |domain| !seen_domains.include?(domain) }
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

    def throttle_delay(delivery, worker_state)
      worker_delay_value = worker_delay_for(worker_state)
      return worker_delay_value if worker_delay_value

      domain_delay = domain_limiter.reserve_or_delay(recipient_domains(delivery))
      return domain_delay if domain_delay > 0

      worker_state[:last_email_started_at] = monotonic_time if worker_state
      nil
    end

    def worker_delay
      @worker_delay ||= non_negative_float_config(
        action_config.fetch('worker_delay', DEFAULT_WORKER_DELAY),
        'email.worker_delay'
      )
    end

    def domain_min_delivery_interval
      @domain_min_delivery_interval ||= non_negative_float_config(
        action_config.fetch(
          'domain_min_delivery_interval',
          DEFAULT_DOMAIN_MIN_DELIVERY_INTERVAL
        ),
        'email.domain_min_delivery_interval'
      )
    end

    def domain_limiter
      @domain_limiter ||= VpsAdmin::API::Notifications::DomainRateLimiter.new(
        interval: domain_min_delivery_interval,
        clock: @monotonic_clock,
        sleeper: @sleeper
      )
    end

    def recipient_domains(delivery)
      mail_log = delivery.mail_log
      domains = %i[to cc bcc].flat_map do |attr|
        address_domains(mail_log&.public_send(attr))
      end
      if domains.empty? && delivery.grouped_delivery?
        addresses = VpsAdmin::API::Events.email_target_addresses(delivery.event, delivery)
        domains.concat(addresses.flat_map { |address| address_domains(address) })
      end

      domains.uniq.presence || ['_unknown']
    rescue StandardError
      ['_unknown']
    end

    protected

    def build_mail_log(delivery)
      event = delivery.event
      template_name = template_name_for_delivery(delivery)

      if generic_group_rendering?(delivery)
        if grouped_template_available?(delivery)
          return ::NotificationTemplate.send_email!(
            :event_group,
            grouped_template_options_for(delivery, event_limit: 100, email: true)
          )
        end

        return ::NotificationTemplate.send_custom_email(
          grouped_email_options_for(delivery)
        )
      end

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

    def grouped_email_options_for(delivery)
      events = delivery.group_events.limit(100).to_a
      event_count = delivery.event_count
      lines = events.map do |event|
        [
          "[#{event.severity}] #{event.subject}",
          event.summary.presence,
          "Event type: #{event.event_type}",
          event.vps && "VPS: ##{event.vps.id} #{event.vps.hostname}"
        ].compact.join("\n")
      end
      if event_count > events.length
        lines << "… and #{event_count - events.length} more events"
      end

      {
        user: delivery.recipient_user || delivery.event.user,
        from: VpsAdmin::API::NotificationTemplateReconciler.default_from,
        to: VpsAdmin::API::Events.email_target_addresses(delivery.event, delivery),
        subject: "#{event_count} grouped vpsAdmin notifications",
        text_plain: lines.join("\n\n")
      }
    end

    def persist_mail_log_snapshot!(mail_log)
      %w[to cc bcc].each do |attr|
        mail_log.public_send("#{attr}=", '') if mail_log.public_send(attr).nil?
      end

      mail_log.save!(validate: false) unless mail_log.persisted?
    end

    def verification_text(target)
      [
        'A vpsAdmin notification target was created for this e-mail address.',
        'Open the link below to verify that notifications may be delivered here:',
        verification_url(target),
        "Target: #{target.label} <#{target.target_value}>",
        'The verification link expires in 24 hours.'
      ].join("\n\n")
    end

    def verification_url(target)
      token = target.verification_credential
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

    def set_message_body(message, mail_log)
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
    end

    def smtp_options
      smtp = config.fetch('smtp', {})
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

    def worker_delay_for(worker_state)
      return unless worker_state && worker_delay > 0

      last_started_at = worker_state[:last_email_started_at]
      return unless last_started_at

      wait_for = last_started_at + worker_delay - monotonic_time
      wait_for if wait_for > 0
    end

    def address_domains(value)
      return [] if value.blank?

      ::Mail::AddressList
        .new(value)
        .addresses
        .filter_map { |address| normalize_domain(address.domain) }
    rescue StandardError
      ['_unknown']
    end

    def normalize_domain(domain)
      domain.to_s.strip.downcase.sub(/\.\z/, '').presence
    end

    def non_negative_float_config(value, name)
      ret = value.to_f
      raise ArgumentError, "#{name} must not be negative" if ret < 0

      ret
    end
  end

  register Email
end
