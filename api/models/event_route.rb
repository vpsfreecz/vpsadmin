class EventRoute < ApplicationRecord
  MAX_ROUTES = 100
  MAX_MATCHERS = 30
  DEFAULT_ROUTE_LABEL = 'Default route'.freeze
  DEFAULT_ROUTE_POSITION = 10_000

  belongs_to :user
  belongs_to :parent_event_route,
             class_name: 'EventRoute',
             foreign_key: :parent_id,
             optional: true
  belongs_to :notification_receiver, optional: true

  has_many :child_event_routes,
           -> { order(:position, :id) },
           class_name: 'EventRoute',
           foreign_key: :parent_id,
           dependent: :destroy
  has_many :event_route_matchers, -> { order(:id) }, dependent: :delete_all
  has_many :events, foreign_key: :matched_event_route_id, dependent: :nullify
  has_many :event_deliveries, dependent: :nullify

  def self.default_route_for(user)
    where(
      user:,
      parent_id: nil,
      label: DEFAULT_ROUTE_LABEL,
      event_type: nil,
      event_type_pattern: nil
    ).order(:position, :id).first
  end

  def self.next_position_for(user, parent_id)
    scope = where(user:, parent_id:)

    return scope.maximum(:position).to_i + 1 if parent_id.present?

    default_route = default_route_for(user)

    return scope.maximum(:position).to_i + 1 unless default_route

    max_before_default = scope.where('position < ?', default_route.position).maximum(:position)
    candidate = max_before_default ? max_before_default + 1 : 0

    return candidate if candidate < default_route.position

    scope.where('position >= ?', default_route.position).update_all('position = position + 1')
    default_route.position
  end

  validates :label, length: { maximum: 255 }, allow_nil: true
  validates :event_type, length: { maximum: 100 }, allow_nil: true
  validates :event_type_pattern, length: { maximum: 100 }, allow_nil: true
  validates :email_template_name, length: { maximum: 100 }, allow_nil: true
  validates :position, numericality: { only_integer: true }
  validate :check_event_type_selector
  validate :check_parent_owner
  validate :check_receiver_owner
  validate :check_parent_loop

  def root?
    parent_id.blank?
  end

  def matches?(event, deadline: nil)
    return false unless event_type_matches?(event.event_type)

    event_route_matchers.all? do |matcher|
      return false if deadline_expired?(deadline)

      ret = matcher.matches?(event)
      return false if deadline_expired?(deadline)

      ret
    end
  end

  def matcher_summary
    selector = event_type || event_type_pattern || '*'
    return selector if event_route_matchers.empty?

    "#{selector}: #{event_route_matchers.map(&:summary).join(' AND ')}"
  end

  def display_label
    label.presence || matcher_summary
  end

  protected

  def check_event_type_selector
    return if event_type.blank? || event_type_pattern.blank?

    errors.add(:event_type_pattern, 'cannot be combined with event type')
  end

  def check_parent_owner
    return unless parent_event_route
    return if parent_event_route.user_id == user_id

    errors.add(:parent_event_route, 'does not belong to the route owner')
  end

  def check_receiver_owner
    return unless notification_receiver
    return if notification_receiver.user_id == user_id

    errors.add(:notification_receiver, 'does not belong to the route owner')
  end

  def check_parent_loop
    route = parent_event_route

    while route
      if route == self
        errors.add(:parent_event_route, 'cannot create a loop')
        return
      end

      route = route.parent_event_route
    end
  end

  def event_type_matches?(tested_type)
    if event_type.present?
      event_type == tested_type
    elsif event_type_pattern.present?
      File.fnmatch?(event_type_pattern, tested_type)
    else
      true
    end
  end

  def deadline_expired?(deadline)
    deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  end
end
