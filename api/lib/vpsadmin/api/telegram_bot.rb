require 'json'
require 'net/http'
require 'uri'

module VpsAdmin::API
  class TelegramBot
    def initialize(token: nil, token_file: nil, api_base_url: nil, config: nil)
      cfg = config || {}
      @token = first_present(
        token,
        ENV.fetch('VPSADMIN_TELEGRAM_BOT_TOKEN', nil),
        cfg['bot_token']
      )
      @token_file = first_present(
        token_file,
        ENV.fetch('VPSADMIN_TELEGRAM_BOT_TOKEN_FILE', nil),
        cfg['bot_token_file']
      )
      @api_base_url = first_present(
        api_base_url,
        ENV.fetch('VPSADMIN_TELEGRAM_API_URL', nil),
        cfg['api_base_url'],
        'https://api.telegram.org'
      ).chomp('/')
    end

    def post_json(method, payload, open_timeout: 5, read_timeout: 15)
      uri = URI.parse("#{@api_base_url}/bot#{bot_token}/#{method}")
      request = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
      request.body = JSON.dump(payload)

      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == 'https',
        open_timeout:,
        read_timeout:
      ) do |http|
        http.request(request)
      end
    end

    protected

    def bot_token
      token = @token.presence || read_token_file
      raise ArgumentError, 'Telegram bot token is not configured' if token.blank?

      token
    end

    def read_token_file
      return if @token_file.blank?

      File.read(@token_file).strip
    end

    def first_present(*values)
      values.find(&:present?).to_s
    end
  end
end
