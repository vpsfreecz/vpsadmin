class EventDeliveryGroup < ApplicationRecord
  STATE_LABELS = {
    'waiting' => 'waiting',
    'overdue' => 'overdue',
    'idle' => 'idle'
  }.freeze

  belongs_to :event_route, optional: true
  belongs_to :notification_receiver, optional: true
  belongs_to :route_owner,
             class_name: 'User',
             foreign_key: :route_owner_id,
             inverse_of: :event_delivery_groups,
             optional: true

  has_many :event_deliveries, dependent: :nullify

  serialize :labels, coder: JSON

  before_validation :snapshot_notification_receiver, on: :create

  validates :group_key, :group_wait_seconds, :group_interval_seconds, presence: true
  validates :group_key, length: { is: 64 }, uniqueness: true
  validates :notification_receiver_label,
            presence: true,
            if: -> { notification_receiver_id.present? }
  validates :group_wait_seconds,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0,
              less_than_or_equal_to: 86_400
            }
  validates :group_interval_seconds,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 60,
              less_than_or_equal_to: 2_592_000
            }
  validate :check_labels

  scope :due, lambda { |now = Time.now|
    where.not(next_flush_at: nil)
         .where(next_flush_at: ..now)
  }

  def grouped?
    true
  end

  def self.state_labels
    STATE_LABELS
  end

  def state
    return 'idle' unless next_flush_at
    return 'overdue' if next_flush_at <= Time.now

    'waiting'
  end

  def event_route_label
    event_route&.display_label
  end

  def route_owner_login
    route_owner&.login
  end

  def group_by
    (labels || {}).keys
  end

  def pending_event_count
    value = self[:pending_event_count] if has_attribute?(:pending_event_count)
    return value.to_i unless value.nil?

    event_deliveries.where(state: 'grouping').distinct.count(:event_id)
  end

  def event_count
    event_deliveries.distinct.count(:event_id)
  end

  def stream_count
    value = self[:stream_count] if has_attribute?(:stream_count)
    return value.to_i unless value.nil?

    event_deliveries.where.not(group_stream_key: nil).distinct.count(:group_stream_key)
  end

  def actions
    event_deliveries.distinct.order(:action).pluck(:action)
  end

  def recalculate_next_flush_at!(now: Time.now)
    first_member_at = event_deliveries
                      .where(state: 'grouping')
                      .minimum(:released_at)
    next_flush_at =
      if first_member_at
        [
          first_member_at + group_wait_seconds,
          last_sealed_at && (last_sealed_at + group_interval_seconds)
        ].compact.max
      end

    update!(next_flush_at:, updated_at: now)
  end

  protected

  def snapshot_notification_receiver
    self.notification_receiver_label ||= notification_receiver&.label
  end

  def check_labels
    errors.add(:labels, 'must be an object') unless labels.is_a?(Hash)
  end
end
