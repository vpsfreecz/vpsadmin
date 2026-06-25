require_relative 'notification_target'

class NotificationReceiverTarget < ApplicationRecord
  self.table_name = 'notification_receiver_targets'

  MAX_TARGETS_PER_RECEIVER = 20
  MAIL_TARGET_VALUE_LIMIT = NotificationTarget::MAIL_TARGET_VALUE_LIMIT
  VERIFICATION_TOKEN_TTL = NotificationTarget::VERIFICATION_TOKEN_TTL
  EMAIL_VERIFICATION_TOKEN_CREATED_AT_KEY = NotificationTarget::EMAIL_VERIFICATION_TOKEN_CREATED_AT_KEY
  EMAIL_VERIFICATION_SENT_AT_KEY = NotificationTarget::EMAIL_VERIFICATION_SENT_AT_KEY
  EMAIL_VERIFICATION_SEND_COOLDOWN = NotificationTarget::EMAIL_VERIFICATION_SEND_COOLDOWN
  PAIRING_TOKEN_CREATED_AT_KEY = NotificationTarget::PAIRING_TOKEN_CREATED_AT_KEY
  SMS_VERIFICATION_CODE_CREATED_AT_KEY = NotificationTarget::SMS_VERIFICATION_CODE_CREATED_AT_KEY
  SMS_VERIFICATION_SENT_AT_KEY = NotificationTarget::SMS_VERIFICATION_SENT_AT_KEY
  SMS_VERIFICATION_FAILED_ATTEMPTS_KEY = NotificationTarget::SMS_VERIFICATION_FAILED_ATTEMPTS_KEY
  SMS_VERIFICATION_LOCKED_UNTIL_KEY = NotificationTarget::SMS_VERIFICATION_LOCKED_UNTIL_KEY
  SMS_VERIFICATION_CODE_TTL = NotificationTarget::SMS_VERIFICATION_CODE_TTL
  SMS_VERIFICATION_SEND_COOLDOWN = NotificationTarget::SMS_VERIFICATION_SEND_COOLDOWN
  SMS_VERIFICATION_MAX_FAILED_ATTEMPTS = NotificationTarget::SMS_VERIFICATION_MAX_FAILED_ATTEMPTS
  SMS_VERIFICATION_LOCKOUT = NotificationTarget::SMS_VERIFICATION_LOCKOUT
  SMS_PHONE_FORMAT = NotificationTarget::SMS_PHONE_FORMAT
  INLINE_TARGET_ATTRIBUTES = %i[
    action
    label
    target_kind
    target_value
    secret
    verification_token
    verified_at
    config
    last_error
  ].freeze

  belongs_to :notification_receiver
  belongs_to :notification_target, autosave: true
  has_many :event_deliveries,
           foreign_key: :notification_receiver_target_id,
           dependent: :nullify

  INLINE_TARGET_ATTRIBUTES.each do |attr|
    define_method(:"#{attr}=") do |value|
      inline_target_attributes[attr] = value
    end
  end

  before_validation :apply_inline_target_attributes
  after_save :clear_inline_target_attributes

  validates :notification_target, presence: true
  validates :notification_target_id, uniqueness: { scope: :notification_receiver_id }, allow_nil: true
  validate :check_target_limit, on: :create
  validate :check_target_owner
  validate :check_notification_target_valid

  delegate :action,
           :action_available?,
           :config,
           :config_json,
           :delivery_method_enabled?,
           :display_target,
           :email_action?,
           :email_verification_required?,
           :custom_target_kind?,
           :default_recipient_target_kind?,
           :identity_key,
           :last_error,
           :secret,
           :secret_present,
           :secret_present?,
           :sms_action?,
           :sms_verification_locked?,
           :sms_verification_send_available?,
           :target_kind,
           :target_value,
           :telegram_action?,
           :telegram_bot_name,
           :telegram_bot_url,
           :telegram_pairing_command,
           :telegram_pairing_url,
           :verification_token,
           :verified,
           :verified?,
           :verified_at,
           :webhook_action?,
           to: :notification_target

  def self.action_labels
    NotificationTarget.action_labels
  end

  def self.target_kind_labels
    NotificationTarget.target_kind_labels
  end

  def self.type_for_attribute(attribute_name, &)
    attr = attribute_name.to_s.to_sym
    return NotificationTarget.type_for_attribute(attribute_name, &) if INLINE_TARGET_ATTRIBUTES.include?(attr)

    super
  end

  def label
    notification_target&.label
  end

  def target_enabled
    notification_target&.enabled? == true
  end

  def delivery_method_enabled
    notification_target&.delivery_method_enabled? == true
  end

  def deliverable?
    notification_target&.deliverable? == true
  end

  def generate_verification_token!(...)
    notification_target.generate_verification_token!(...)
  end

  def generate_email_verification_token!(...)
    notification_target.generate_email_verification_token!(...)
  end

  def generate_sms_verification_code!(...)
    notification_target.generate_sms_verification_code!(...)
  end

  def ensure_sms_verification_code!(...)
    notification_target.ensure_sms_verification_code!(...)
  end

  def ensure_email_verification_token!(...)
    notification_target.ensure_email_verification_token!(...)
  end

  def email_verification_send_available?(...)
    notification_target.email_verification_send_available?(...)
  end

  def confirm_sms_verification_code!(...)
    notification_target.confirm_sms_verification_code!(...)
  end

  def confirm_email_verification_token!(...)
    notification_target.confirm_email_verification_token!(...)
  end

  def pair_telegram_chat!(...)
    notification_target.pair_telegram_chat!(...)
  end

  def mark_verified!(...)
    notification_target.mark_verified!(...)
  end

  def mark_email_verification_sent!(...)
    notification_target.mark_email_verification_sent!(...)
  end

  def mark_sms_verification_sent!(...)
    notification_target.mark_sms_verification_sent!(...)
  end

  def skip_delivery_method_enabled_validation=(value)
    @skip_delivery_method_enabled_validation = value
    notification_target.skip_delivery_method_enabled_validation = value if notification_target
  end

  def raw_verification_token
    notification_target.send(:raw_verification_token)
  end

  def verification_token_expired?(now = Time.now)
    return false if raw_verification_token.blank? || verified?

    created_at = notification_target.send(:verification_token_created_at)
    created_at ||= [notification_target.updated_at, updated_at].compact.min
    return false if created_at.nil?

    ttl = sms_action? ? SMS_VERIFICATION_CODE_TTL : VERIFICATION_TOKEN_TTL
    created_at < now - ttl
  end

  def [](attribute_name)
    attr = attribute_name.to_s.to_sym
    return notification_target[attribute_name] if INLINE_TARGET_ATTRIBUTES.include?(attr) && notification_target

    super
  end

  protected

  def check_target_limit
    return unless notification_receiver

    count = notification_receiver
            .notification_receiver_targets
            .where.not(id:)
            .count
    return if count < MAX_TARGETS_PER_RECEIVER

    errors.add(:base, "cannot have more than #{MAX_TARGETS_PER_RECEIVER} receiver targets")
  end

  def check_target_owner
    return unless notification_receiver && notification_target
    return if notification_receiver.user_id == notification_target.user_id

    errors.add(:notification_target, 'does not belong to the receiver owner')
  end

  def check_notification_target_valid
    return unless notification_target
    return if notification_target.valid?

    notification_target.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end

  def inline_target_attributes
    @inline_target_attributes ||= {}
  end

  def apply_inline_target_attributes
    return if inline_target_attributes.empty?
    return unless notification_receiver

    if notification_target
      notification_target.assign_attributes(inline_target_attributes)
    else
      return if inline_target_attributes[:action].blank?

      action = inline_target_attributes[:action].to_s
      target_kind = inline_target_kind_for(action)
      identity_key = NotificationTarget.identity_key_for(
        action,
        target_kind,
        inline_target_attributes[:target_value],
        inline_target_attributes[:secret]
      )

      if identity_key.present?
        existing = notification_receiver.user.notification_targets.find_by(
          action:,
          identity_key:
        )

        if existing
          self.notification_target = existing
          return
        end
      end

      self.notification_target = notification_receiver.user.notification_targets.new(
        inline_target_attributes.merge(enabled: true)
      )
    end

    return unless defined?(@skip_delivery_method_enabled_validation)

    notification_target.skip_delivery_method_enabled_validation =
      @skip_delivery_method_enabled_validation
  end

  def clear_inline_target_attributes
    @inline_target_attributes = {}
  end

  def inline_target_kind_for(action)
    kind = inline_target_attributes[:target_kind].to_s.presence

    if action == 'email'
      kind || 'default_recipient'
    elsif kind.blank? || kind == 'default_recipient'
      'custom'
    else
      kind
    end
  end
end

NotificationReceiverAction = NotificationReceiverTarget
