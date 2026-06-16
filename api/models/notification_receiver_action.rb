require 'securerandom'
require 'uri'

class NotificationReceiverAction < ApplicationRecord
  MAX_ACTIONS_PER_RECEIVER = 20

  ACTION_LABELS = {
    'email' => 'E-mail',
    'telegram' => 'Telegram',
    'webhook' => 'Webhook'
  }.freeze

  TARGET_KIND_LABELS = {
    'default_recipient' => 'default recipient',
    'custom' => 'custom target'
  }.freeze

  belongs_to :notification_receiver
  has_many :event_deliveries, dependent: :nullify

  enum :action, %i[email telegram webhook], suffix: true
  enum :target_kind, %i[default_recipient custom], suffix: true

  serialize :config, coder: JSON

  before_validation :set_default_target_kind
  before_validation :set_default_label

  validates :action, :target_kind, :label, presence: true
  validates :label, length: { maximum: 255 }, allow_nil: true
  validates :template_name, length: { maximum: 100 }, allow_nil: true
  validates :verification_token, length: { maximum: 255 }, allow_nil: true
  validate :check_action_limit, on: :create
  validate :check_target

  def self.action_labels
    ACTION_LABELS
  end

  def self.target_kind_labels
    TARGET_KIND_LABELS
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
    return true if email_action?
    return true if webhook_action?

    verified?
  end

  def generate_verification_token!
    update!(
      verification_token: SecureRandom.urlsafe_base64(24),
      verified_at: nil
    )
  end

  def display_target
    case action
    when 'email'
      target_value.presence || 'Account e-mail'
    when 'telegram'
      target_value.presence || 'Linked Telegram chat'
    when 'webhook'
      target_value.presence || 'Webhook URL'
    else
      target_value.presence || target_kind.tr('_', ' ')
    end
  end

  protected

  def set_default_label
    self.label = ACTION_LABELS[action] if label.blank? && action.present?
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

  def check_target
    case action
    when 'email'
      check_email_target
    when 'telegram'
      check_telegram_target
    when 'webhook'
      check_webhook_target
    end
  end

  def check_email_target
    return if default_recipient_target_kind?

    if target_value.blank?
      errors.add(:target_value, "can't be blank")
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
end
