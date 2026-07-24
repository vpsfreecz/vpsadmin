class EventDeliveryGroup < ApplicationRecord
  belongs_to :event_route, optional: true
  belongs_to :route_owner,
             class_name: 'User',
             foreign_key: :route_owner_id,
             optional: true

  has_many :event_deliveries, dependent: :nullify

  serialize :labels, coder: JSON

  validates :action, :group_key, :group_wait_seconds, :group_interval_seconds,
            presence: true
  validates :action,
            inclusion: { in: ->(_) { VpsAdmin::API::Notifications::Actions.names } }
  validates :group_key, length: { is: 64 }, uniqueness: true
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

  scope :due_for_action, lambda { |action, now = Time.now|
    where(action:)
      .where.not(next_flush_at: nil)
      .where(next_flush_at: ..now)
  }

  def grouped?
    true
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

  def check_labels
    errors.add(:labels, 'must be an object') unless labels.is_a?(Hash)
  end
end
