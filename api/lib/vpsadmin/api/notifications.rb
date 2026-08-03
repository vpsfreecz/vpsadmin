require 'bunny'
require 'json'
require 'time'
require 'yaml'

module VpsAdmin::API
  module Notifications
    class DeliveryPreparationTerminalError < StandardError
      attr_reader :delivery_state

      def initialize(delivery_state, message)
        @delivery_state = delivery_state
        super(message)
      end
    end

    EXCHANGE_NAME = 'vpsadmin.notifications'.freeze
    GROUPING_QUEUE = 'vpsadmin.notifications.grouping'.freeze
    GROUPING_ROUTING_KEY = 'delivery.grouping'.freeze
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

    VpsAdmin::API::Events::ActionPolicies.register_external(
      'notifications.sms_callback',
      kind: :internal_state,
      reason: 'delivery transport state must not create a routeable feedback event',
      atomic: false
    )

    module_function

    def queue_name(action)
      DeliveryActions.queue_name(action)
    end

    def routing_key(action)
      DeliveryActions.routing_key(action)
    end

    def webhook_payload_for(delivery)
      DeliveryActions.fetch('webhook').payload_for(delivery)
    end

    def telegram_configured?(config = Config.load)
      DeliveryActions.build('telegram', config:).available?
    end

    def sms_configured?(config = Config.load)
      DeliveryActions.build('sms', config:).available?
    end

    def send_email_verification!(target)
      DeliveryActions.fetch('email').send_verification!(target)
    end

    def send_sms_verification_code!(target)
      DeliveryActions.fetch('sms').send_verification!(target)
    end

    def apply_sms_gateway_callback!(...)
      DeliveryActions.build('sms').apply_gateway_callback!(...)
    end

    class Config
      class << self
        def load(path = default_path)
          return {} unless File.exist?(path)

          config = YAML.safe_load_file(path, aliases: true) || {}
          DeliveryActions.validate_deployment_contract!(config['delivery_contract'])
          config
        end

        def default_path
          ENV['VPSADMIN_NOTIFICATIONS_CONFIG'].presence ||
            File.join(VpsAdmin::API.root, 'config', 'notifications.yml')
        end
      end
    end
  end
end

require_relative 'notifications/delivery_action'
require_relative 'notifications/rate_limits'
Dir[File.expand_path('notifications/delivery_actions/*.rb', __dir__)].each do |path|
  require path
end
VpsAdmin::API::Notifications::DeliveryActions.finalize!

module VpsAdmin::API::Notifications
  EmailVerificationDeliveryError = DeliveryActions::Email::VerificationDeliveryError
  WebhookResponseError = DeliveryActions::Webhook::ResponseError
  TelegramResponseError = DeliveryActions::Telegram::ResponseError
  SmsGatewayResponseError = DeliveryActions::Sms::GatewayResponseError
  SmsCallbackAuthenticationError = DeliveryActions::Sms::CallbackAuthenticationError
  SmsCallbackConflictError = DeliveryActions::Sms::CallbackConflictError
end

require_relative 'notifications/publisher'
require_relative 'notifications/grouping'
require_relative 'notifications/retry'
require_relative 'notifications/dispatcher'
