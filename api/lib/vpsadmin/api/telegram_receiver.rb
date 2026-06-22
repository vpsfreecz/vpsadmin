require 'json'
require 'rack'

module VpsAdmin::API
  class TelegramReceiver
    UPDATE_OFFSET_CATEGORY = 'notifications'.freeze
    UPDATE_OFFSET_NAME = 'telegram_update_offset'.freeze
    START_COMMAND = %r{\A/start(?:@\w+)?(?:\s+([A-Za-z0-9_-]+))?\s*\z}
    DEFAULT_LIMIT = 100
    DEFAULT_TIMEOUT = 50
    DEFAULT_RETRY_DELAY = 5
    SECRET_TOKEN_HEADER = 'HTTP_X_TELEGRAM_BOT_API_SECRET_TOKEN'.freeze

    def initialize(
      config: VpsAdmin::API::Notifications::Config.load,
      bot: nil,
      logger: $stderr,
      sleeper: ->(seconds) { sleep(seconds) }
    )
      @config = config.fetch('telegram', {})
      @telegram_bot = bot
      @logger = logger
      @sleeper = sleeper
      @running = true
    end

    def poll_once
      response = telegram_bot.post_json(
        'getUpdates',
        get_updates_payload,
        read_timeout: polling_read_timeout
      )
      body = response_body(response)
      updates = response_updates!(response, body)

      process_updates(updates, save_offset: true)
    end

    def run_polling
      trap_signals
      prepare_polling!

      while @running
        begin
          poll_once
        rescue StandardError => e
          @logger.puts "Telegram receiver polling failed: #{e.class}: #{e.message}"
          sleep_seconds(retry_delay)
        end
      end
    end

    def webhook_app
      lambda do |env|
        request = Rack::Request.new(env)
        unless request.path_info == webhook_path
          next rack_response(404, 'Not found')
        end

        unless request.post?
          next rack_response(405, 'Method not allowed')
        end

        unless webhook_secret_valid?(env)
          next rack_response(403, 'Forbidden')
        end

        update = JSON.parse(request.body.read.to_s)
        unless update.is_a?(Hash)
          next rack_response(400, 'Bad request')
        end

        stats = process_updates([update], save_offset: false)
        rack_json_response(200, ok: true, stats:)
      rescue JSON::ParserError
        rack_response(400, 'Bad request')
      rescue StandardError => e
        @logger.puts "Telegram receiver webhook failed: #{e.class}: #{e.message}"
        rack_response(500, 'Internal server error')
      end
    end

    def register_webhook!
      return unless webhook_auto_register?

      response = telegram_bot.post_json('setWebhook', set_webhook_payload)
      body = response_body(response)

      return if telegram_success?(response, body)

      raise "Telegram setWebhook failed: #{telegram_error_summary(response, body)}"
    end

    def webhook_host
      webhook_config.fetch('listen_address', '127.0.0.1')
    end

    def webhook_port
      webhook_config.fetch('port', 9293).to_i
    end

    def webhook_path
      webhook_config.fetch('path', '/_telegram/webhook')
    end

    protected

    def prepare_polling!
      return unless polling_config.fetch('delete_webhook', true)

      response = telegram_bot.post_json('deleteWebhook', { drop_pending_updates: false })
      body = response_body(response)

      return if telegram_success?(response, body)

      raise "Telegram deleteWebhook failed: #{telegram_error_summary(response, body)}"
    end

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

    def process_updates(updates, save_offset:)
      stats = { paired: 0, rejected: 0, ignored: 0 }
      max_update_id = nil

      updates.each do |update|
        if update.has_key?('update_id')
          max_update_id = [max_update_id, update['update_id'].to_i].compact.max
        end

        stats[process_update(update)] += 1
      end

      save_update_offset(max_update_id + 1) if save_offset && max_update_id
      stats
    end

    def response_updates!(response, body)
      unless telegram_success?(response, body)
        raise "Telegram getUpdates failed: #{telegram_error_summary(response, body)}"
      end

      result = body['result']
      raise 'Telegram getUpdates returned non-array result' unless result.is_a?(Array)

      result
    end

    def process_update(update)
      message = update['message']
      return :ignored unless message.is_a?(Hash)

      match = START_COMMAND.match(message['text'].to_s)
      return :ignored unless match

      token = match[1]
      if token.blank?
        reply_to_pairing_message(message, missing_token_message)
        return :rejected
      end

      action = ::NotificationReceiverAction.find_by(
        action: 'telegram',
        verification_token: token
      )
      unless action
        reply_to_pairing_message(message, invalid_token_message)
        return :rejected
      end

      pair_action(action, token, message)
    end

    def pair_action(action, token, message)
      chat = message['chat']
      chat_id = chat && chat['id']
      return :ignored if chat_id.nil?

      state, reply = action.with_lock do
        next :ignored unless action.telegram_action? && action.verification_token == token

        if action.verification_token_expired?
          action.generate_verification_token!(
            last_error: 'Telegram pairing token expired; use the new command shown below'
          )
          next [:rejected, expired_token_message]
        end

        unless chat['type'] == 'private'
          action.generate_verification_token!(
            last_error: 'Telegram pairing must be sent from a private chat'
          )
          next [:rejected, private_chat_required_message]
        end

        action.pair_telegram_chat!(chat_id)
        [:paired, pairing_succeeded_message]
      end

      reply_to_chat(chat_id, reply) if reply
      state
    end

    def reply_to_pairing_message(message, text)
      chat = message['chat']
      chat_id = chat && chat['id']
      return if chat_id.nil?

      reply_to_chat(chat_id, text)
    end

    def reply_to_chat(chat_id, text)
      response = telegram_bot.post_json(
        'sendMessage',
        {
          chat_id:,
          text:
        }
      )
      body = response_body(response)
      return if telegram_success?(response, body)

      @logger.puts "Telegram receiver reply failed: #{telegram_error_summary(response, body)}"
    rescue StandardError => e
      @logger.puts "Telegram receiver reply failed: #{e.class}: #{e.message}"
    end

    def missing_token_message
      'To pair Telegram with vpsAdmin, open the Telegram action detail in vpsAdmin and use the pairing link or command shown there.'
    end

    def invalid_token_message
      'This vpsAdmin Telegram pairing token is not valid. Open the Telegram action detail in vpsAdmin and create a new pairing command.'
    end

    def expired_token_message
      'This vpsAdmin Telegram pairing token has expired. Open the Telegram action detail in vpsAdmin and use the newly generated command.'
    end

    def private_chat_required_message
      'Telegram pairing must be completed in a private chat with this bot. Open the bot directly and use the pairing command from vpsAdmin.'
    end

    def pairing_succeeded_message
      'Telegram pairing succeeded. vpsAdmin notifications can now be delivered to this chat.'
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

    def set_webhook_payload
      payload = {
        url: webhook_public_url,
        allowed_updates: ['message']
      }
      payload[:secret_token] = webhook_secret_token if webhook_secret_token.present?
      payload
    end

    def webhook_public_url
      webhook_config.fetch('public_url') do
        raise 'Telegram webhook public URL is not configured'
      end
    end

    def webhook_secret_valid?(env)
      expected = webhook_secret_token
      return true if expected.blank?

      env[SECRET_TOKEN_HEADER] == expected
    end

    def webhook_secret_token
      webhook_config.fetch('secret_token', nil)
    end

    def webhook_auto_register?
      webhook_config.fetch('auto_register', true)
    end

    def rack_response(status, body, content_type: 'text/plain')
      [
        status,
        {
          'content-type' => content_type,
          'content-length' => body.bytesize.to_s
        },
        [body]
      ]
    end

    def rack_json_response(status, payload)
      rack_response(status, JSON.dump(payload), content_type: 'application/json')
    end

    def response_body(response)
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
      return 'invalid JSON response' if body.nil?
      return 'non-object JSON response' unless body.is_a?(Hash)

      body['description'].presence || "HTTP #{response.code}"
    end

    def timeout
      polling_config.fetch(
        'timeout',
        ENV.fetch('VPSADMIN_TELEGRAM_UPDATES_TIMEOUT', DEFAULT_TIMEOUT)
      ).to_i.clamp(0, 50)
    end

    def polling_read_timeout
      [timeout + 5, 15].max
    end

    def limit
      polling_config.fetch(
        'limit',
        ENV.fetch('VPSADMIN_TELEGRAM_UPDATES_LIMIT', DEFAULT_LIMIT)
      ).to_i.clamp(1, 100)
    end

    def retry_delay
      polling_config.fetch('retry_delay', DEFAULT_RETRY_DELAY).to_i.clamp(1, 3600)
    end

    def telegram_bot
      @telegram_bot ||= VpsAdmin::API::TelegramBot.new(config: @config)
    end

    def polling_config
      @config.fetch('polling', {})
    end

    def webhook_config
      @config.fetch('webhook', {})
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
end
