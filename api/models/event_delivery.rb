class EventDelivery < ApplicationRecord
  DIRECT_REQUEST_EVENT_TYPES = %w[
    request.created
    request.updated
    request.resolved
  ].freeze
  DIRECT_SYSTEM_TEMPLATE_EVENT_TYPES = %w[
    outage.announced
    outage.updated
  ].freeze

  ACTION_LABELS = {
    'email' => 'E-mail',
    'telegram' => 'Telegram',
    'webhook' => 'Webhook'
  }.freeze

  TARGET_KIND_LABELS = {
    'default_recipient' => 'default recipient',
    'custom' => 'custom target'
  }.freeze

  STATE_LABELS = {
    'planned' => 'planned',
    'queued' => 'queued',
    'sent' => 'sent',
    'skipped' => 'skipped',
    'failed' => 'failed',
    'canceled' => 'canceled'
  }.freeze

  belongs_to :event
  belongs_to :event_route, optional: true
  belongs_to :notification_receiver, optional: true
  belongs_to :notification_receiver_action, optional: true
  belongs_to :mail_log, optional: true
  belongs_to :delivery_transaction,
             class_name: 'Transaction',
             foreign_key: :transaction_id,
             optional: true

  enum :action, %i[email telegram webhook], suffix: true
  enum :target_kind, %i[default_recipient custom], suffix: true
  enum :state, %i[planned queued sent skipped failed canceled], suffix: true

  validates :action, :target_kind, :state, presence: true
  validates :target_label, :provider_message_id, length: { maximum: 255 }, allow_nil: true
  validates :template_name, length: { maximum: 100 }, allow_nil: true
  validates :response_status, numericality: { only_integer: true }, allow_nil: true
  validates :attempt_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.action_labels
    ACTION_LABELS
  end

  def self.target_kind_labels
    TARGET_KIND_LABELS
  end

  def self.state_labels
    STATE_LABELS
  end

  def notification_receiver_available?
    return true if direct_email_delivery?

    notification_receiver&.enabled? && !notification_receiver.mute?
  end

  def direct_email_delivery?
    direct_request_email_delivery? || direct_system_template_email_delivery?
  end

  def direct_request_email_delivery?
    return false unless email_action? &&
                        notification_receiver.nil? &&
                        notification_receiver_action.nil? &&
                        default_recipient_target_kind? &&
                        target_value.present?
    return false unless event&.user_id.nil?
    return false unless DIRECT_REQUEST_EVENT_TYPES.include?(event.event_type)

    params = event.parameters || {}
    recipient = params['recipient_email'] || params[:recipient_email]

    (params['role'] || params[:role]).to_s == 'user' &&
      recipient.present? &&
      target_value == recipient.to_s
  end

  def direct_system_template_email_delivery?
    return false unless email_action? &&
                        notification_receiver.nil? &&
                        notification_receiver_action.nil? &&
                        default_recipient_target_kind? &&
                        target_value.blank?
    return false unless event&.user_id.nil?
    return false unless DIRECT_SYSTEM_TEMPLATE_EVENT_TYPES.include?(event.event_type)

    params = event.parameters || {}
    (params['role'] || params[:role]).to_s == 'generic'
  end
end
