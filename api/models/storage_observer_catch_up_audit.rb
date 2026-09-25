require 'json'

class StorageObserverCatchUpAudit < ApplicationRecord
  enum :event_type, %i[requested completed], prefix: :event

  validates :request_id, :reason, :freeze_epoch,
            :after_chain_id, :page_limit, :created_at, presence: true
  validates :request_id, uniqueness: { scope: :event_type }
  validates :actor_user_login, presence: true, length: { maximum: 128 }
  validates :reason, length: { maximum: 255 }
  validates :page_limit, numericality: { only_integer: true, in: 1..100 }
  validates :freeze_epoch, :after_chain_id,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :actor_user_id, :actor_user_session_id,
            numericality: { only_integer: true, greater_than: 0 }
  validates :result_json, length: { maximum: 32_768 }, allow_nil: true
  validate :result_matches_event
  validate :safe_actor_text

  def self.record_completion!(request, result)
    json = JSON.generate(result)
    raise ArgumentError, 'catch-up result exceeds audit limit' if json.bytesize > 32_768

    create!(
      request_id: request.request_id, event_type: :completed,
      actor_user_id: request.actor_user_id, actor_user_login: request.actor_user_login,
      actor_user_session_id: request.actor_user_session_id,
      reason: request.reason,
      freeze_epoch: request.freeze_epoch, after_chain_id: request.after_chain_id,
      page_limit: request.page_limit, result_json: json, created_at: Time.current
    )
  end

  def readonly?
    persisted?
  end

  private

  def result_matches_event
    return if event_requested? && result_json.nil?
    return if event_completed? && result_json.present?

    errors.add(:result_json, 'must match the event type')
  end

  def safe_actor_text
    errors.add(:reason, 'contains a control character') if reason.to_s.match?(/[[:cntrl:]]/)
    errors.add(:actor_user_login, 'contains a control character') if actor_user_login.to_s.match?(/[[:cntrl:]]/)
    errors.add(:actor_user_login, 'is required') if actor_user_login.to_s.strip.empty?
  end
end
