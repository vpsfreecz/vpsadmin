require 'securerandom'
require 'time'
require 'uri'

class NotificationReceiverAction < ApplicationRecord
  MAX_ACTIONS_PER_RECEIVER = 20
  MAIL_TARGET_VALUE_LIMIT = 500
  VERIFICATION_TOKEN_TTL = 24 * 60 * 60
  PAIRING_TOKEN_CREATED_AT_KEY = 'telegram_pairing_token_created_at'.freeze

  TARGET_KIND_LABELS = {
    'default_recipient' => 'default recipient',
    'custom' => 'custom target'
  }.freeze

  belongs_to :notification_receiver
  has_many :event_deliveries, dependent: :nullify

  enum :target_kind, %i[default_recipient custom], suffix: true

  serialize :config, coder: JSON

  before_validation :set_default_target_kind
  before_validation :set_default_label
  before_validation :clean_email_target
  before_validation :reset_telegram_verification_after_untrusted_change

  validates :action, :target_kind, :label, presence: true
  validates :action, inclusion: { in: ->(_) { VpsAdmin::API::Notifications::Actions.names } }
  validates :label, length: { maximum: 255 }, allow_nil: true
  validates :verification_token, length: { maximum: 255 }, allow_nil: true
  validate :check_action_limit, on: :create
  validate :check_action_available
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

    VpsAdmin::API::Notifications::Actions.known?(action)
  end

  def action_available?
    VpsAdmin::API::Notifications::Actions.available?(action)
  end

  def verification_token_expired?(now = Time.now)
    return false if verification_token.blank?
    return false if verified?

    created_at = verification_token_created_at || updated_at
    return false if created_at.nil?

    created_at < now - VERIFICATION_TOKEN_TTL
  end

  def generate_verification_token!(last_error: nil)
    update!(
      verification_token: SecureRandom.urlsafe_base64(24),
      verified_at: nil,
      last_error:,
      config: telegram_config_with_pairing_token_timestamp
    )
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

  def email_action?
    action == 'email'
  end

  def webhook_action?
    action == 'webhook'
  end

  def telegram_action?
    action == 'telegram'
  end

  protected

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

  def reset_telegram_verification_after_untrusted_change
    return if @telegram_pairing_update
    return unless persisted?

    if will_save_change_to_action? && !telegram_action?
      self.verification_token = nil
      self.verified_at = nil
      return
    end

    return unless telegram_action?
    return unless will_save_change_to_action? ||
                  will_save_change_to_target_kind? ||
                  will_save_change_to_target_value?

    self.verified_at = nil
    ensure_telegram_verification_token
  end

  def action_definition
    VpsAdmin::API::Notifications::Actions.fetch(action)
  end

  def ensure_telegram_verification_token
    self.verification_token ||= SecureRandom.urlsafe_base64(24)
    self.config = telegram_config_with_pairing_token_timestamp
  end

  def telegram_config_with_pairing_token_timestamp
    (config || {}).merge(PAIRING_TOKEN_CREATED_AT_KEY => Time.now.iso8601)
  end

  def telegram_config_without_pairing_token_timestamp
    (config || {}).except(PAIRING_TOKEN_CREATED_AT_KEY)
  end

  def verification_token_created_at
    value = (config || {})[PAIRING_TOKEN_CREATED_AT_KEY]
    return if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
