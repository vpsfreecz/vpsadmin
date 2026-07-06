class NotificationReceiver < ApplicationRecord
  DEFAULT_EMAIL_LABEL = 'Default'.freeze
  LEGACY_DEFAULT_EMAIL_LABEL = 'Default e-mail'.freeze
  DEFAULT_MUTE_LABEL = 'Mute'.freeze
  LEGACY_DEFAULT_MUTE_LABEL = 'Do not notify'.freeze
  ADMIN_REQUEST_ROUTE_LABEL = 'Admin request notifications'.freeze
  MAX_RECEIVERS_PER_USER = 50
  DEFAULT_EMAIL_DESCRIPTION = 'Default notification receiver'.freeze
  DEFAULT_MUTE_DESCRIPTION = 'Default muted notification receiver'.freeze
  LEGACY_DEFAULT_EMAIL_DESCRIPTION = 'Created from the existing mailer setting'.freeze
  LEGACY_DEFAULT_MUTE_DESCRIPTION = 'Created from the disabled mailer setting'.freeze

  belongs_to :user
  has_many :notification_receiver_targets, -> { order(:position, :id) }, dependent: :delete_all
  has_many :notification_targets, through: :notification_receiver_targets
  has_many :notification_receiver_actions,
           -> { order(:position, :id) },
           class_name: 'NotificationReceiverTarget',
           dependent: :delete_all
  has_many :event_routes, dependent: :nullify
  has_many :event_deliveries, dependent: :nullify

  before_validation :set_default_label

  validates :label, presence: true, length: { maximum: 255 }
  validate :check_receiver_limit, on: :create

  def self.ensure_defaults_for!(user)
    transaction do
      email_receiver = ensure_default_email_receiver_for!(user)
      ensure_default_mute_receiver_for!(user)
      ensure_default_route!(user, email_receiver, role: ::EventRoute::DEFAULT_ACCOUNT_ROUTE_ROLE_VALUE)
      ensure_default_route!(user, email_receiver, role: ::EventRoute::DEFAULT_ADMIN_ROUTE_ROLE_VALUE)
    end
  end

  def self.ensure_admin_request_defaults!
    transaction do
      ::User.where(level: 90..).find_each do |admin|
        ensure_admin_request_defaults_for!(admin)
      end
    end
  end

  def self.ensure_admin_request_defaults_for!(admin)
    email_receiver = ensure_default_email_receiver_for!(admin)
    ensure_default_mute_receiver_for!(admin)
    route = admin_request_route_for(admin)

    if route
      route.update!(notification_receiver: email_receiver) if route.notification_receiver.nil?
      return route
    end

    route = admin.event_routes.create!(
      notification_receiver: email_receiver,
      label: ADMIN_REQUEST_ROUTE_LABEL,
      event_type_pattern: 'request.*',
      subject_scope: ::EventRoute.subject_scopes.fetch('visible'),
      position: ::EventRoute.prepend_position_for(admin)
    )
    route.event_route_matchers.create!(
      field: 'roles',
      operator: 'contains',
      value: 'account'
    )
    route
  end

  def self.ensure_default_email_receiver_for!(user)
    receiver = default_email_receiver_for(user) || create_default_email_receiver!(user)
    normalize_default_email_receiver!(receiver)
    ensure_default_email_action!(receiver)
    receiver
  end

  def self.ensure_default_mute_receiver_for!(user)
    receiver = default_mute_receiver_for(user) || create_default_mute_receiver!(user)
    normalize_default_mute_receiver!(receiver)
    receiver
  end

  def self.default_receiver_for(user)
    default_email_receiver_for(user) || default_mute_receiver_for(user)
  end

  def self.default_email_receiver_for(user)
    where(
      user:,
      label: [DEFAULT_EMAIL_LABEL, LEGACY_DEFAULT_EMAIL_LABEL],
      mute: false,
      description: [
        DEFAULT_EMAIL_DESCRIPTION,
        LEGACY_DEFAULT_EMAIL_DESCRIPTION
      ]
    ).order(:id).first
  end

  def self.default_mute_receiver_for(user)
    where(
      user:,
      label: [DEFAULT_MUTE_LABEL, LEGACY_DEFAULT_MUTE_LABEL],
      mute: true,
      description: [
        DEFAULT_MUTE_DESCRIPTION,
        LEGACY_DEFAULT_MUTE_DESCRIPTION
      ]
    ).order(:id).first
  end

  def self.create_default_email_receiver!(user)
    new(
      user:,
      label: DEFAULT_EMAIL_LABEL,
      description: DEFAULT_EMAIL_DESCRIPTION,
      mute: false
    ).tap { |receiver| receiver.save!(validate: false) }
  end

  def self.create_default_mute_receiver!(user)
    new(
      user:,
      label: DEFAULT_MUTE_LABEL,
      description: DEFAULT_MUTE_DESCRIPTION,
      mute: true
    ).tap { |receiver| receiver.save!(validate: false) }
  end

  def self.ensure_default_email_action!(receiver)
    target = receiver.user.notification_targets.find_or_create_by!(
      action: 'email',
      identity_key: 'default'
    ) do |t|
      t.label = DEFAULT_EMAIL_LABEL
      t.target_kind = 'default_recipient'
      t.skip_delivery_method_enabled_validation = true
    end
    if target.label != DEFAULT_EMAIL_LABEL
      target.update_columns(label: DEFAULT_EMAIL_LABEL, updated_at: Time.now)
    end

    receiver.notification_receiver_targets.find_or_create_by!(
      notification_target: target
    ) do |link|
      link.position = next_receiver_target_position(receiver)
    end
  end

  def self.next_receiver_target_position(receiver)
    receiver.notification_receiver_targets.maximum(:position).to_i + 1
  end

  def self.ensure_default_route!(user, receiver, role:)
    route = ::EventRoute.default_route_for(user, role:)

    if route
      route.update!(notification_receiver: receiver) if route.notification_receiver.nil?
      return route
    end

    route = user.event_routes.create!(
      notification_receiver: receiver,
      label: default_route_label(role),
      position: default_route_position(role)
    )
    route.event_route_matchers.create!(
      field: ::EventRoute::DEFAULT_ROUTE_MATCHER_FIELD,
      operator: ::EventRoute::DEFAULT_ROUTE_MATCHER_OPERATOR,
      value: ::EventRoute::DEFAULT_ROUTE_MATCHER_VALUE
    )
    route.event_route_matchers.create!(
      field: ::EventRoute::DEFAULT_ROUTE_ROLE_FIELD,
      operator: ::EventRoute::DEFAULT_ROUTE_ROLE_OPERATOR,
      value: role.to_s
    )
    route
  end

  def self.default_route_label(role)
    role.to_s == ::EventRoute::DEFAULT_ADMIN_ROUTE_ROLE_VALUE ? ::EventRoute::DEFAULT_ADMIN_ROUTE_LABEL : ::EventRoute::DEFAULT_ROUTE_LABEL
  end

  def self.default_route_position(role)
    role.to_s == ::EventRoute::DEFAULT_ADMIN_ROUTE_ROLE_VALUE ? ::EventRoute::DEFAULT_ADMIN_ROUTE_POSITION : ::EventRoute::DEFAULT_ROUTE_POSITION
  end

  def self.admin_request_route_for(admin)
    ::EventRoute.active
                .where(
                  user: admin,
                  parent_id: nil,
                  label: ADMIN_REQUEST_ROUTE_LABEL,
                  event_type: nil,
                  event_type_pattern: 'request.*',
                  subject_scope: ::EventRoute.subject_scopes.fetch('visible')
                )
                .includes(:event_route_matchers)
                .order(:position, :id)
                .detect do |route|
                  route.event_route_matchers.any? do |matcher|
                    matcher.field == 'roles' &&
                      matcher.operator == 'contains' &&
                      matcher.value.to_s == 'account'
                  end
                end
  end

  def self.normalize_default_mute_receiver!(receiver)
    return if receiver.label == DEFAULT_MUTE_LABEL &&
              receiver.description == DEFAULT_MUTE_DESCRIPTION

    receiver.update!(
      label: DEFAULT_MUTE_LABEL,
      description: DEFAULT_MUTE_DESCRIPTION
    )
  end

  def self.normalize_default_email_receiver!(receiver)
    return if receiver.label == DEFAULT_EMAIL_LABEL &&
              receiver.description == DEFAULT_EMAIL_DESCRIPTION

    receiver.update!(
      label: DEFAULT_EMAIL_LABEL,
      description: DEFAULT_EMAIL_DESCRIPTION
    )
  end

  def display_action_summary
    return 'Muted' if mute?

    count = notification_receiver_targets.count
    count == 1 ? '1 target' : "#{count} targets"
  end

  def active_actions
    return notification_receiver_actions.none if mute? || !enabled?

    notification_receiver_actions.select(&:deliverable?)
  end

  protected

  def set_default_label
    return if label.present?

    self.label = mute? ? DEFAULT_MUTE_LABEL : 'Receiver'
  end

  def check_receiver_limit
    return unless user
    return if user.notification_receivers.where.not(id:).count < MAX_RECEIVERS_PER_USER

    errors.add(:base, "cannot have more than #{MAX_RECEIVERS_PER_USER} notification receivers")
  end
end
