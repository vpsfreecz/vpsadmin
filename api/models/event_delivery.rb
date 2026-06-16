class EventDelivery < ApplicationRecord
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
    notification_receiver&.enabled? && !notification_receiver.mute?
  end
end
