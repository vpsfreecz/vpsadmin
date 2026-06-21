require 'json'

module VpsAdmin::API::Tasks
  class Telegram < Base
    UPDATE_OFFSET_CATEGORY = 'notifications'.freeze
    UPDATE_OFFSET_NAME = 'telegram_update_offset'.freeze
    START_COMMAND = %r{\A/start(?:@\w+)?\s+([A-Za-z0-9_-]+)\s*\z}
    DEFAULT_LIMIT = 100

    def poll_pairing_updates
      response = telegram_bot.post_json(
        'getUpdates',
        get_updates_payload,
        read_timeout: polling_read_timeout
      )
      body = response_body(response)
      updates = response_updates!(response, body)

      stats = { paired: 0, rejected: 0, ignored: 0 }
      max_update_id = nil

      updates.each do |update|
        if update.has_key?('update_id')
          max_update_id = [max_update_id, update['update_id'].to_i].compact.max
        end
        stats[process_update(update)] += 1
      end

      save_update_offset(max_update_id + 1) if max_update_id
      stats
    end

    protected

    def get_updates_payload
      payload = {
        allowed_updates: ['message'],
        limit:,
        timeout:
      }
      offset = update_offset
      payload[:offset] = offset if offset
      payload
    end

    def response_body(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      nil
    end

    def response_updates!(response, body)
      unless response.code.to_i.between?(200, 299) && body.is_a?(Hash) && body['ok']
        raise "Telegram getUpdates failed: #{telegram_error_summary(response, body)}"
      end

      result = body['result']
      raise 'Telegram getUpdates returned non-array result' unless result.is_a?(Array)

      result
    end

    def telegram_error_summary(response, body)
      return 'invalid JSON response' if body.nil?
      return 'non-object JSON response' unless body.is_a?(Hash)

      body['description'].presence || "HTTP #{response.code}"
    end

    def process_update(update)
      message = update['message']
      return :ignored unless message.is_a?(Hash)

      match = START_COMMAND.match(message['text'].to_s)
      return :ignored unless match

      action = ::NotificationReceiverAction.find_by(
        action: 'telegram',
        verification_token: match[1]
      )
      return :ignored unless action

      pair_action(action, match[1], message)
    end

    def pair_action(action, token, message)
      chat = message['chat']
      chat_id = chat && chat['id']
      return :ignored if chat_id.nil?

      action.with_lock do
        next :ignored unless action.telegram_action? && action.verification_token == token

        if action.verification_token_expired?
          action.generate_verification_token!(
            last_error: 'Telegram pairing token expired; use the new command shown below'
          )
          next :rejected
        end

        unless chat['type'] == 'private'
          action.generate_verification_token!(
            last_error: 'Telegram pairing must be sent from a private chat'
          )
          next :rejected
        end

        action.pair_telegram_chat!(chat_id)
        :paired
      end
    end

    def update_offset
      value = ::SysConfig.get(UPDATE_OFFSET_CATEGORY, UPDATE_OFFSET_NAME)
      offset = value.to_i
      offset > 0 ? offset : nil
    end

    def save_update_offset(offset)
      rec = ::SysConfig.where(
        category: UPDATE_OFFSET_CATEGORY,
        name: UPDATE_OFFSET_NAME
      ).first_or_initialize
      rec.data_type ||= 'Integer'
      rec.value = offset
      rec.save!
    end

    def timeout
      telegram_config.fetch('updates_timeout', ENV.fetch('VPSADMIN_TELEGRAM_UPDATES_TIMEOUT', '0')).to_i.clamp(0, 50)
    end

    def polling_read_timeout
      [timeout + 5, 15].max
    end

    def limit
      telegram_config.fetch('updates_limit', ENV.fetch('VPSADMIN_TELEGRAM_UPDATES_LIMIT', DEFAULT_LIMIT)).to_i.clamp(1, 100)
    end

    def telegram_bot
      @telegram_bot ||= VpsAdmin::API::TelegramBot.new(config: telegram_config)
    end

    def telegram_config
      @telegram_config ||= VpsAdmin::API::Notifications::Config.load.fetch('telegram', {})
    end
  end
end
