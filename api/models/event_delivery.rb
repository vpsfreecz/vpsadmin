class EventDelivery < ApplicationRecord
  TARGET_KIND_LABELS = {
    'default_recipient' => 'default recipient',
    'custom' => 'custom target'
  }.freeze

  STATE_LABELS = {
    'prepared' => 'prepared',
    'released' => 'released',
    'sending' => 'sending',
    'sent' => 'sent',
    'skipped' => 'skipped',
    'failed' => 'failed',
    'canceled' => 'canceled',
    'accepted' => 'accepted',
    'aborted' => 'aborted'
  }.freeze

  ABORTABLE_STATES = %w[prepared released].freeze
  NON_DELIVERED_FINAL_STATES = %w[skipped canceled aborted].freeze

  belongs_to :event
  belongs_to :event_routing_context, optional: true
  belongs_to :event_route, optional: true
  belongs_to :notification_receiver, optional: true
  belongs_to :notification_target, optional: true
  belongs_to :notification_receiver_target, optional: true
  belongs_to :notification_receiver_action,
             class_name: 'NotificationReceiverTarget',
             foreign_key: :notification_receiver_target_id,
             optional: true
  belongs_to :mail_log, optional: true
  belongs_to :delivery_transaction,
             class_name: 'Transaction',
             foreign_key: :transaction_id,
             optional: true
  has_many :event_delivery_attempts, dependent: :delete_all

  enum :target_kind, %i[default_recipient custom], suffix: true
  enum :state, %i[prepared released sending sent skipped failed canceled accepted aborted], suffix: true

  serialize :response_headers, coder: JSON

  validates :action, :target_kind, :state, presence: true
  validates :action, inclusion: { in: ->(_) { VpsAdmin::API::Notifications::Actions.names } }
  validates :target_label, :provider_message_id, length: { maximum: 255 }, allow_nil: true
  validates :template_name, length: { maximum: 100 }, allow_nil: true
  validates :response_status, numericality: { only_integer: true }, allow_nil: true
  validates :attempt_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :due, -> { where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.now) }
  scope :email_action, -> { where(action: 'email') }
  scope :telegram_action, -> { where(action: 'telegram') }
  scope :webhook_action, -> { where(action: 'webhook') }
  scope :sms_action, -> { where(action: 'sms') }

  def self.action_labels
    VpsAdmin::API::Notifications::Actions.labels
  end

  def self.target_kind_labels
    VpsAdmin::API::Notifications::Actions.target_kind_labels
  end

  def self.state_labels
    STATE_LABELS
  end

  def self.abort_unsent_for_transaction_chain!(chain)
    chain_id = chain.respond_to?(:id) ? chain.id : chain
    return [] if chain_id.blank?

    aborted_event_ids = []
    now = Time.now

    transaction do
      rows = joins(:delivery_transaction)
             .where(
               transactions: { transaction_chain_id: chain_id },
               state: ABORTABLE_STATES,
               attempt_count: 0,
               provider_message_id: nil
             )
             .where(no_delivery_attempts_sql)
             .lock
             .pluck(:id, :event_id)

      ids = rows.map(&:first)

      if ids.any?
        where(
          id: ids,
          state: ABORTABLE_STATES,
          attempt_count: 0,
          provider_message_id: nil
        ).where(no_delivery_attempts_sql).update_all(
          state: states.fetch('aborted'),
          next_attempt_at: nil,
          error_summary: "transaction chain ##{chain_id} failed before notification was sent",
          updated_at: now
        )

        aborted_event_ids = where(id: ids, state: 'aborted').pluck(:event_id).uniq
      end

      aborted_event_ids.each { |event_id| recompute_abort_routing_state!(event_id, now:) }
    end

    aborted_event_ids
  end

  def self.no_delivery_attempts_sql
    'NOT EXISTS (
      SELECT 1
      FROM event_delivery_attempts
      WHERE event_delivery_attempts.event_delivery_id = event_deliveries.id
    )'
  end

  def self.recompute_abort_routing_state!(event_id, now:)
    rows = where(event_id:).pluck(:state, :event_routing_context_id)
    return if rows.empty?

    final_states = NON_DELIVERED_FINAL_STATES.map { |state| states.fetch(state) }
    aborted_state = states.fetch('aborted')
    normalized_rows = rows.map do |state, context_id|
      [state.is_a?(String) ? states.fetch(state) : state, context_id]
    end

    if normalized_rows.any? { |state, _| state == aborted_state } &&
       normalized_rows.all? { |state, _| final_states.include?(state) }
      ::Event.where(id: event_id).update_all(
        routing_state: ::Event.routing_states.fetch('aborted'),
        updated_at: now
      )
    end

    normalized_rows.map(&:second).compact.uniq.each do |context_id|
      context_rows = normalized_rows.select { |_, row_context_id| row_context_id == context_id }
      next unless context_rows.any? { |state, _| state == aborted_state }
      next unless context_rows.all? { |state, _| final_states.include?(state) }

      ::EventRoutingContext.where(id: context_id).update_all(
        routing_state: ::EventRoutingContext.routing_states.fetch('aborted'),
        updated_at: now
      )
    end
  end

  private_class_method :recompute_abort_routing_state!
  private_class_method :no_delivery_attempts_sql

  def response_headers_json
    JSON.dump(response_headers || {})
  end

  def public_payload
    return payload unless sms_action? && payload.present?

    data = JSON.parse(payload)
    return payload unless data.is_a?(Hash) && data.has_key?('callback_secret')

    JSON.dump(data.except('callback_secret'))
  rescue JSON::ParserError
    payload
  end

  def notification_receiver_label
    notification_receiver&.label
  end

  def event_route_label
    event_route&.display_label
  end

  def delivery_transaction_chain_id
    delivery_transaction&.transaction_chain_id
  end

  def delivery_transaction_chain_label
    delivery_transaction&.transaction_chain&.label
  end

  def notification_receiver_action_label
    notification_target&.label || notification_receiver_action&.label
  end

  def notification_receiver_action_display_target
    notification_target&.display_target || notification_receiver_action&.display_target
  end

  def notification_target_label
    notification_target&.label
  end

  def notification_target_display_target
    notification_target&.display_target
  end

  def event_user_id
    event&.user_id
  end

  def recipient_user
    event_routing_context&.recipient_user ||
      notification_target&.user ||
      notification_receiver_action&.notification_receiver&.user ||
      notification_receiver&.user ||
      event&.user
  end

  def recipient_user_id
    recipient_user&.id
  end

  def recipient_user_login
    recipient_user&.login
  end

  def event_user_login
    event&.user&.login
  end

  def event_vps_id
    event&.vps_id
  end

  def event_vps_hostname
    event&.vps&.hostname
  end

  def event_type
    event&.event_type
  end

  def event_subject
    event&.subject
  end

  def event_severity
    event&.severity
  end

  def event_created_at
    event&.created_at
  end

  def mail_to
    mail_log&.to
  end

  def mail_cc
    mail_log&.cc
  end

  def mail_from
    mail_log&.from
  end

  def mail_reply_to
    mail_log&.reply_to
  end

  def mail_return_path
    mail_log&.return_path
  end

  def mail_message_id
    mail_log&.message_id
  end

  def mail_subject
    mail_log&.subject
  end

  def mail_text_plain
    mail_log&.text_plain
  end

  def mail_text_html
    mail_log&.text_html
  end

  def notification_receiver_available?
    return true if direct_email_delivery?

    notification_receiver&.enabled? && !notification_receiver.mute?
  end

  def receiver_action_available?
    if notification_receiver_id.present? || notification_receiver_target_id.present?
      return false unless notification_receiver

      target = notification_receiver_action || notification_receiver_target
      return false unless target
    else
      target = notification_target
    end

    return true if target.nil? && direct_email_delivery?

    action_definition.receiver_action_available?(target)
  rescue KeyError
    false
  end

  def delivery_method_enabled?
    return true if direct_email_delivery?

    user = notification_target&.user ||
           notification_receiver_action&.notification_receiver&.user ||
           notification_receiver&.user ||
           event_routing_context&.recipient_user ||
           event&.user
    return true unless user

    user.notification_delivery_method_enabled?(action) == true
  end

  def due_for_delivery?
    (released_state? || sending_state?) &&
      (next_attempt_at.nil? || next_attempt_at <= Time.now)
  end

  def direct_email_delivery?
    return false unless email_action? &&
                        notification_receiver.nil? &&
                        notification_target.nil? &&
                        notification_receiver_action.nil? &&
                        event&.user_id.nil?

    direct_request_email_delivery? ||
      direct_system_template_email_delivery? ||
      direct_custom_email_delivery?
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

  def direct_request_email_delivery?
    default_recipient_target_kind? &&
      target_value.present? &&
      VpsAdmin::API::Events.default_email_target_for(event).to_s == target_value.to_s
  end

  def direct_system_template_email_delivery?
    default_recipient_target_kind? &&
      target_value.blank? &&
      VpsAdmin::API::Events.system_template_email?(event)
  end

  def direct_custom_email_delivery?
    custom_target_kind? &&
      target_value.present? &&
      VpsAdmin::API::Events.custom_email_target_for(event).to_s == target_value.to_s
  end

  protected

  def action_definition
    VpsAdmin::API::Notifications::Actions.fetch(action)
  end
end
