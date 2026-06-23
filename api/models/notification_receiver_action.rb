require 'securerandom'
require 'active_support/security_utils'
require 'time'
require 'uri'

class NotificationReceiverAction < ApplicationRecord
  MAX_ACTIONS_PER_RECEIVER = 20
  MAIL_TARGET_VALUE_LIMIT = 500
  VERIFICATION_TOKEN_TTL = 24 * 60 * 60
  PAIRING_TOKEN_CREATED_AT_KEY = 'telegram_pairing_token_created_at'.freeze
  SMS_VERIFICATION_CODE_CREATED_AT_KEY = 'sms_verification_code_created_at'.freeze
  SMS_VERIFICATION_SENT_AT_KEY = 'sms_verification_sent_at'.freeze
  SMS_VERIFICATION_FAILED_ATTEMPTS_KEY = 'sms_verification_failed_attempts'.freeze
  SMS_VERIFICATION_LOCKED_UNTIL_KEY = 'sms_verification_locked_until'.freeze
  SMS_VERIFICATION_CODE_TTL = 10 * 60
  SMS_VERIFICATION_SEND_COOLDOWN = 60
  SMS_VERIFICATION_MAX_FAILED_ATTEMPTS = 5
  SMS_VERIFICATION_LOCKOUT = 10 * 60
  SMS_PHONE_FORMAT = /\A\+[1-9][0-9]{6,14}\z/

  TARGET_KIND_LABELS = {
    'default_recipient' => 'default recipient',
    'custom' => 'custom target'
  }.freeze

  belongs_to :notification_receiver
  has_many :event_deliveries, dependent: :nullify

  enum :target_kind, %i[default_recipient custom], suffix: true

  serialize :config, coder: JSON

  attr_accessor :skip_delivery_method_enabled_validation

  before_validation :set_default_target_kind
  before_validation :set_default_label
  before_validation :clean_email_target
  before_validation :clean_sms_target
  before_validation :reset_action_verification_after_untrusted_change

  validates :action, :target_kind, :label, presence: true
  validates :action, inclusion: { in: ->(_) { VpsAdmin::API::Notifications::Actions.names } }
  validates :label, length: { maximum: 255 }, allow_nil: true
  validates :verification_token, length: { maximum: 255 }, allow_nil: true
  validate :check_action_limit, on: :create
  validate :check_action_available
  validate :check_delivery_method_enabled
  validate :check_target

  def self.action_labels
    VpsAdmin::API::Notifications::Actions.available_labels
  end

  def self.target_kind_labels
    VpsAdmin::API::Notifications::Actions.target_kind_labels
  end

  def verified?
    verified_at.present?
  end

  def verified
    verified?
  end

  def secret_present?
    secret.present?
  end

  def secret_present
    secret_present?
  end

  def config_json
    JSON.dump(config || {})
  end

  def deliverable?
    return false unless enabled?
    return false unless action_available?
    return false unless delivery_method_enabled?

    VpsAdmin::API::Notifications::Actions.known?(action)
  end

  def action_available?
    VpsAdmin::API::Notifications::Actions.available?(action)
  end

  def verification_token_expired?(now = Time.now)
    return false if raw_verification_token.blank?
    return false if verified?

    created_at = verification_token_created_at || updated_at
    return false if created_at.nil?

    ttl = sms_action? ? SMS_VERIFICATION_CODE_TTL : VERIFICATION_TOKEN_TTL
    created_at < now - ttl
  end

  def generate_verification_token!(last_error: nil)
    update!(
      verification_token: SecureRandom.urlsafe_base64(24),
      verified_at: nil,
      last_error:,
      config: telegram_config_with_pairing_token_timestamp
    )
  end

  def generate_sms_verification_code!
    update!(
      verification_token: sms_verification_code,
      verified_at: nil,
      last_error: nil,
      config: sms_config_with_code_timestamp
    )
  end

  def ensure_sms_verification_code!
    return if raw_verification_token.present? && !verification_token_expired?

    generate_sms_verification_code!
  end

  def confirm_sms_verification_code!(code)
    return false unless sms_action?
    return false if raw_verification_token.blank? || verification_token_expired?
    return false if sms_verification_locked?

    submitted = code.to_s.strip
    if submitted.bytesize != raw_verification_token.bytesize ||
       !ActiveSupport::SecurityUtils.secure_compare(submitted, raw_verification_token)
      record_sms_verification_failure!
      return false
    end

    update!(
      verification_token: nil,
      verified_at: Time.now,
      last_error: nil,
      config: sms_config_without_verification_state
    )
    true
  end

  def pair_telegram_chat!(chat_id)
    @telegram_pairing_update = true
    update!(
      target_kind: :custom,
      target_value: chat_id.to_s,
      verification_token: nil,
      verified_at: Time.now,
      last_error: nil,
      config: telegram_config_without_pairing_token_timestamp
    )
  ensure
    @telegram_pairing_update = false
  end

  def display_target
    action_definition.display_target_for(self)
  rescue KeyError
    target_value.presence || target_kind.tr('_', ' ')
  end

  def telegram_pairing_command
    return unless telegram_action? && raw_verification_token.present? && !verified?

    "/start #{raw_verification_token}"
  end

  def telegram_bot_url
    return unless telegram_action?

    username = telegram_bot_username
    return if username.blank?

    "https://t.me/#{username}"
  end

  def telegram_pairing_url
    return unless telegram_pairing_command

    bot_url = telegram_bot_url
    return if bot_url.blank?

    "#{bot_url}?start=#{raw_verification_token}"
  end

  def verification_token
    return if sms_action?

    raw_verification_token
  end

  def email_action?
    action == 'email'
  end

  def webhook_action?
    action == 'webhook'
  end

  def telegram_action?
    action == 'telegram'
  end

  def sms_action?
    action == 'sms'
  end

  def delivery_method_enabled?
    return false if action.blank?
    return false unless VpsAdmin::API::Notifications::Actions.known?(action)

    notification_receiver&.user&.notification_delivery_method_enabled?(action) == true
  end

  def sms_verification_sent_at
    value = (config || {})[SMS_VERIFICATION_SENT_AT_KEY]
    return if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end

  def sms_verification_send_available?(now = Time.now)
    sent_at = sms_verification_sent_at
    sent_at.nil? || sent_at <= now - SMS_VERIFICATION_SEND_COOLDOWN
  end

  def sms_verification_locked?(now = Time.now)
    locked_until = sms_verification_locked_until
    locked_until.present? && locked_until > now
  end

  def mark_sms_verification_sent!
    update!(
      config: (config || {}).merge(SMS_VERIFICATION_SENT_AT_KEY => Time.now.iso8601),
      last_error: nil
    )
  end

  protected

  def raw_verification_token
    self[:verification_token]
  end

  def set_default_label
    self.label = action_definition.label if label.blank? && action.present?
  rescue KeyError
    nil
  end

  def set_default_target_kind
    return if action.blank?

    if email_action?
      self.target_kind ||= 'default_recipient'
    elsif target_kind.blank? || default_recipient_target_kind?
      self.target_kind = 'custom'
    end
  end

  def check_action_limit
    return unless notification_receiver

    count = notification_receiver
            .notification_receiver_actions
            .where.not(id:)
            .count
    return if count < MAX_ACTIONS_PER_RECEIVER

    errors.add(:base, "cannot have more than #{MAX_ACTIONS_PER_RECEIVER} receiver actions")
  end

  def check_action_available
    return if action.blank?
    return unless new_record? || will_save_change_to_action?
    return if action_available?

    errors.add(:action, 'is not available')
  end

  def check_delivery_method_enabled
    return if skip_delivery_method_enabled_validation
    return if action.blank?
    return if notification_receiver.nil?
    return unless VpsAdmin::API::Notifications::Actions.known?(action)
    return if delivery_method_enabled?

    errors.add(:action, 'is not enabled for this user')
  end

  def check_target
    action_definition.validate_receiver_action!(self)
  rescue KeyError
    nil
  end

  def check_email_target
    return if default_recipient_target_kind?

    if target_value.blank?
      errors.add(:target_value, "can't be blank")
      return
    end

    if target_value.length > MAIL_TARGET_VALUE_LIMIT
      errors.add(:target_value, "is too long (maximum is #{MAIL_TARGET_VALUE_LIMIT} characters)")
      return
    end

    target_value.split(',').each do |mail|
      next if mail.strip.include?('@')

      errors.add(:target_value, "'#{mail}' is not a valid e-mail address")
    end
  end

  def check_telegram_target
    return if custom_target_kind?

    errors.add(:target_kind, 'must be custom')
  end

  def check_sms_target
    unless custom_target_kind?
      errors.add(:target_kind, 'must be custom')
      return
    end

    if target_value.blank?
      errors.add(:target_value, "can't be blank")
      return
    end

    return if target_value.match?(SMS_PHONE_FORMAT)

    errors.add(:target_value, 'must be an E.164 phone number, e.g. +420123456789')
  end

  def check_webhook_target
    if target_value.blank?
      errors.add(:target_value, "can't be blank")
      return
    end

    uri = URI.parse(target_value)
    return if uri.is_a?(URI::HTTP) && uri.host.present?

    errors.add(:target_value, 'must be an HTTP or HTTPS URL')
  rescue URI::InvalidURIError
    errors.add(:target_value, 'must be an HTTP or HTTPS URL')
  end

  def clean_email_target
    return unless email_action? && custom_target_kind? && target_value

    target_value.gsub!(/\s/, '')
  end

  def clean_sms_target
    return unless sms_action? && target_value

    target_value.strip!
    target_value.gsub!(/\s/, '')
  end

  def reset_action_verification_after_untrusted_change
    return if @telegram_pairing_update
    return unless persisted?

    if will_save_change_to_action? && !telegram_action? && !sms_action?
      self.verification_token = nil
      self.verified_at = nil
      return
    end

    return unless telegram_action? || sms_action?
    return unless will_save_change_to_action? ||
                  will_save_change_to_target_kind? ||
                  will_save_change_to_target_value?

    self.verified_at = nil
    telegram_action? ? ensure_telegram_verification_token : ensure_sms_verification_code(regenerate: true)
  end

  def action_definition
    VpsAdmin::API::Notifications::Actions.fetch(action)
  end

  def ensure_telegram_verification_token
    self.verification_token ||= SecureRandom.urlsafe_base64(24)
    self.config = telegram_config_with_pairing_token_timestamp
  end

  def ensure_sms_verification_code(regenerate: false)
    if regenerate || raw_verification_token.blank? || verification_token_expired?
      self.verification_token = sms_verification_code
    end
    self.config = sms_config_with_code_timestamp
  end

  def sms_verification_code
    SecureRandom.random_number(1_000_000).to_s.rjust(6, '0')
  end

  def telegram_config_with_pairing_token_timestamp
    (config || {}).merge(PAIRING_TOKEN_CREATED_AT_KEY => Time.now.iso8601)
  end

  def telegram_config_without_pairing_token_timestamp
    (config || {}).except(PAIRING_TOKEN_CREATED_AT_KEY)
  end

  def sms_config_with_code_timestamp
    (config || {})
      .except(SMS_VERIFICATION_FAILED_ATTEMPTS_KEY, SMS_VERIFICATION_LOCKED_UNTIL_KEY)
      .merge(SMS_VERIFICATION_CODE_CREATED_AT_KEY => Time.now.iso8601)
  end

  def sms_config_without_verification_state
    (config || {}).except(
      SMS_VERIFICATION_CODE_CREATED_AT_KEY,
      SMS_VERIFICATION_SENT_AT_KEY,
      SMS_VERIFICATION_FAILED_ATTEMPTS_KEY,
      SMS_VERIFICATION_LOCKED_UNTIL_KEY
    )
  end

  def verification_token_created_at
    value = if sms_action?
              (config || {})[SMS_VERIFICATION_CODE_CREATED_AT_KEY]
            else
              (config || {})[PAIRING_TOKEN_CREATED_AT_KEY]
            end
    return if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end

  def telegram_bot_username
    cfg = VpsAdmin::API::Notifications::Config.load.fetch('telegram', {})
    username = cfg['bot_username'].presence || cfg['botUsername'].presence
    username&.delete_prefix('@')
  end

  def record_sms_verification_failure!
    attempts = (config || {})[SMS_VERIFICATION_FAILED_ATTEMPTS_KEY].to_i + 1
    attrs = (config || {}).merge(SMS_VERIFICATION_FAILED_ATTEMPTS_KEY => attempts)
    if attempts >= SMS_VERIFICATION_MAX_FAILED_ATTEMPTS
      attrs[SMS_VERIFICATION_LOCKED_UNTIL_KEY] = (Time.now + SMS_VERIFICATION_LOCKOUT).iso8601
    end

    update!(config: attrs)
  end

  def sms_verification_locked_until
    value = (config || {})[SMS_VERIFICATION_LOCKED_UNTIL_KEY]
    return if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
