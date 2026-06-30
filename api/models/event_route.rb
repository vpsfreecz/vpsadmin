class EventRoute < ApplicationRecord
  MAX_ROUTES = 100
  MAX_MATCHERS = 30
  DEFAULT_ROUTE_LABEL = 'Default route'.freeze
  DEFAULT_ROUTE_POSITION = 10_000
  DEFAULT_ROUTE_MATCHER_FIELD = 'default_routed'.freeze
  DEFAULT_ROUTE_MATCHER_OPERATOR = '=='.freeze
  DEFAULT_ROUTE_MATCHER_VALUE = 'true'.freeze
  SUBJECT_SCOPE_LABELS = {
    'self' => 'self',
    'visible' => 'visible'
  }.freeze

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
  has_many :event_deliveries, dependent: :nullify
  has_many :event_route_matches, dependent: :delete_all

  enum :subject_scope, %i[self visible], suffix: true

  def self.default_route_for(user)
    active
      .where(
        user:,
        parent_id: nil,
        event_type: nil,
        event_type_pattern: nil,
        subject_scope: subject_scopes.fetch('self')
      )
      .includes(:event_route_matchers)
      .order(:position, :id)
      .detect(&:default_catch_all?)
  end

  def self.active
    where(spent_at: nil)
      .where('expires_at IS NULL OR expires_at > ?', Time.now)
  end

  def self.subject_scope_labels
    SUBJECT_SCOPE_LABELS
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

  def self.prepend_position_for(user, parent_id = nil)
    scope = where(user:, parent_id:)
    min = scope.minimum(:position)

    min ? min - 1 : 0
  end

  validates :label, length: { maximum: 255 }, allow_nil: true
  validates :event_type, length: { maximum: 100 }, allow_nil: true
  validates :event_type_pattern, length: { maximum: 100 }, allow_nil: true
  validates :template_name, length: { maximum: 100 }, allow_nil: true
  validates :position, numericality: { only_integer: true }
  validate :check_event_type_selector
  validate :check_parent_owner
  validate :check_receiver_owner
  validate :check_parent_loop

  def root?
    parent_id.blank?
  end

  def matches?(event, deadline: nil)
    matches_in_context?(
      VpsAdmin::API::Events::RouteContext.self_context(event),
      deadline:
    )
  end

  def matches_in_context?(route_context, deadline: nil)
    return false unless active?
    return false unless subject_scope_matches?(route_context)
    return false unless event_type_matches?(route_context.event.event_type)

    event_route_matchers.all? do |matcher|
      return false if deadline_expired?(deadline)

      ret = matcher.matches?(route_context.event, route_context:)
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

  def active?
    return false if spent_at.present?
    return false if expires_at && expires_at <= Time.now

    true
  end

  def spend!
    update!(enabled: false, spent_at: Time.now) if single_use? && spent_at.blank?
  end

  def default_catch_all?
    return false unless parent_id.nil?
    return false unless label == DEFAULT_ROUTE_LABEL
    return false unless self_subject_scope?
    return false if event_type.present? || event_type_pattern.present?

    matchers = event_route_matchers.to_a
    return false unless matchers.size == 1

    matcher = matchers.first
    matcher.field == DEFAULT_ROUTE_MATCHER_FIELD &&
      matcher.operator == DEFAULT_ROUTE_MATCHER_OPERATOR &&
      matcher.value.to_s == DEFAULT_ROUTE_MATCHER_VALUE
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

  def subject_scope_matches?(route_context)
    case subject_scope
    when 'self'
      route_context.self_subject?
    when 'visible'
      route_context.visible?
    else
      false
    end
  end

  def deadline_expired?(deadline)
    deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
  end
end
