require 'erb'

module VpsAdmin::API::Notifications::DeliveryActions
  class Telegram < Base
    class ResponseError < VpsAdmin::API::Notifications::DeliveryFailure
      def initialize(response_status, response_body, message)
        super(message, response_status:, response_body:)
      end
    end

    DEFAULT_CONCURRENCY = 2
    HTML_PARSE_MODE = 'HTML'.freeze
    LINK_PREVIEW_OPTIONS = { is_disabled: true }.freeze
    TEXT_LIMIT = 4096

    action :telegram,
           label: 'Telegram',
           queue: 'vpsadmin.notifications.telegram',
           routing_key: 'delivery.telegram',
           default_concurrency: DEFAULT_CONCURRENCY,
           default_rate_limits: {
             minute: 20,
             hour: 200,
             day: 1000,
             week: 2500
           },
           template_context_fallbacks: [:email],
           templates: true
    target_kind :custom, label: 'custom target'

    def available?
      telegram = action_config
      return false if telegram.has_key?('enabled') && !truthy_config?(telegram['enabled'])

      truthy_config?(telegram.fetch('configured', false)) || configured_token?(telegram)
    rescue KeyError
      false
    end

    def validate_target(target)
      return if target.custom_target_kind?

      target.errors.add(:target_kind, 'must be custom')
    end

    def identity_key(target_kind:, target_value:, secret: nil)
      target_value.to_s.strip.presence&.then { |value| "chat:#{value}" }
    end

    def display_target(target)
      if target.target_value.present?
        "Telegram chat #{target.target_value}"
      else
        'Linked Telegram chat'
      end
    end

    def target_available?(target)
      target.verified? && target.target_value.present?
    end

    def plan_delivery(context:, route:, receiver:, receiver_action:)
      if receiver_action.target_value.blank?
        return context.skip(route, receiver, receiver_action, 'Telegram chat is not linked')
      end
      unless receiver_action.verified?
        return context.skip(route, receiver, receiver_action, 'Telegram chat is not verified')
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

      delivery.update!(
        payload: JSON.dump(payload_for(delivery))
      )
    end

    def deliver(delivery)
      response = telegram_bot.post_json('sendMessage', delivery_payload(delivery))
      body = response_body(response)

      unless success?(response, body)
        raise ResponseError.new(
          response.code.to_i,
          truncate_body(response.body),
          error_summary(response, body)
        )
      end

      VpsAdmin::API::Notifications::DeliveryResult.new(
        provider_message_id: provider_message_id(body),
        response_status: response.code.to_i,
        response_body: truncate_body(response.body)
      )
    end

    def payload_for(delivery)
      {
        chat_id: delivery.target_value
      }.merge(message_for(delivery))
    end

    def text_for(delivery)
      message_for(delivery).fetch(:text)
    end

    protected

    def configured_token?(telegram)
      telegram.fetch('bot_token', nil).present? ||
        telegram.fetch('bot_token_file', nil).present? ||
        ENV['VPSADMIN_TELEGRAM_BOT_TOKEN'].present? ||
        ENV['VPSADMIN_TELEGRAM_BOT_TOKEN_FILE'].present?
    end

    def message_for(delivery)
      return grouped_message_for(delivery) if generic_group_rendering?(delivery)

      event = delivery.event
      template_name = template_name_for_delivery(delivery)

      if template_name
        rendered = ::NotificationTemplate.render_telegram!(
          template_name,
          VpsAdmin::API::Events.template_options_for(event, delivery, action: :telegram)
        )
        html = rendered[:html].to_s

        if html.present? && html.length <= TEXT_LIMIT
          return {
            text: html,
            parse_mode: HTML_PARSE_MODE,
            link_preview_options: LINK_PREVIEW_OPTIONS
          }
        end

        return { text: truncate_text(rendered.fetch(:text)) }
      end

      subject = if event.vps
                  "VPS #{event.vps.hostname} (##{event.vps.id}): #{event.subject}"
                else
                  event.subject
                end
      text_lines = [
        "[#{event.severity}] #{subject}",
        "Event: #{event.event_type}"
      ]
      html_lines = [
        "<b>#{html_escape("[#{event.severity}] #{subject}")}</b>",
        "Event: <code>#{html_escape(event.event_type)}</code>"
      ]

      url = webui_url(event)
      if url.present?
        link_label = webui_link_label(event)
        text_lines << "Link: #{link_label}: #{url}"
        html_lines << %(Link: <a href="#{html_escape(url)}">#{html_escape(link_label)}</a>)
      end

      html = html_lines.join("\n")
      if html.length <= TEXT_LIMIT
        return {
          text: html,
          parse_mode: HTML_PARSE_MODE,
          link_preview_options: LINK_PREVIEW_OPTIONS
        }
      end

      { text: truncate_text(text_lines.join("\n")) }
    end

    def grouped_message_for(delivery)
      if grouped_template_available?(delivery)
        rendered = ::NotificationTemplate.render_telegram!(
          :event_group,
          grouped_template_options_for(delivery, event_limit: 30)
        )
        html = rendered[:html].to_s

        if html.present? && html.length <= TEXT_LIMIT
          return {
            text: html,
            parse_mode: HTML_PARSE_MODE,
            link_preview_options: LINK_PREVIEW_OPTIONS
          }
        end

        return { text: truncate_text(rendered.fetch(:text)) }
      end

      events = delivery.group_events.limit(30).to_a
      event_count = delivery.event_count
      lines = ["#{event_count} grouped vpsAdmin notifications"]
      lines.concat(events.map { |event| "[#{event.severity}] #{event.subject}" })
      lines << "… and #{event_count - events.length} more" if event_count > events.length

      { text: truncate_text(lines.join("\n")) }
    end

    def webui_url(event)
      base_url = VpsAdmin::API::Events.webui_url
      return if base_url.blank?

      if event.vps
        "#{base_url}/?page=adminvps&action=info&veid=#{event.vps.id}"
      else
        "#{base_url}/?page=notifications&action=event_show&id=#{event.id}"
      end
    end

    def webui_link_label(event)
      event.vps ? 'VPS details' : 'event details'
    end

    def html_escape(value)
      ERB::Util.html_escape(value.to_s)
    end

    def truncate_text(text)
      text.to_s[0, TEXT_LIMIT]
    end

    def delivery_payload(delivery)
      payload = JSON.parse(delivery.payload.to_s)
      raise 'Telegram payload is not an object' unless payload.is_a?(Hash)

      ret = {
        chat_id: payload.fetch('chat_id'),
        text: payload.fetch('text')
      }
      ret[:parse_mode] = payload['parse_mode'] if payload['parse_mode'].present?
      if payload['link_preview_options'].present?
        ret[:link_preview_options] = payload['link_preview_options']
      end
      ret
    rescue JSON::ParserError
      payload_for(delivery)
    end

    def response_body(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      nil
    end

    def success?(response, body)
      response.code.to_i.between?(200, 299) && body.is_a?(Hash) && body.fetch('ok', false)
    end

    def error_summary(response, body)
      return 'Telegram API returned invalid JSON' if body.nil?
      return 'Telegram API returned non-object JSON' unless body.is_a?(Hash)

      description = body['description']
      return "Telegram API: #{description}" if description.present?
      return "Telegram returned HTTP #{response.code}" unless response.code.to_i.between?(200, 299)

      'Telegram API did not confirm success'
    end

    def provider_message_id(body)
      result = body['result']
      result['message_id']&.to_s if result.is_a?(Hash)
    end

    def telegram_bot
      @telegram_bot ||= VpsAdmin::API::TelegramBot.new(config: action_config)
    end
  end

  register Telegram
end
