class EventDeliveryAttempt < ApplicationRecord
  STATE_LABELS = {
    'running' => 'running',
    'succeeded' => 'succeeded',
    'failed' => 'failed'
  }.freeze

  belongs_to :event_delivery

  enum :state, %i[running succeeded failed], suffix: true

  serialize :response_headers, coder: JSON

  validates :action, :state, :attempt_number, presence: true
  validates :action, inclusion: { in: ->(_) { VpsAdmin::API::Notifications::Actions.names } }
  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  validates :provider_message_id, length: { maximum: 255 }, allow_nil: true
  validates :response_status, numericality: { only_integer: true }, allow_nil: true

  def self.state_labels
    STATE_LABELS
  end

  def response_headers_json
    JSON.dump(response_headers || {})
  end
end
