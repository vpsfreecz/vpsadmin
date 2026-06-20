class NotificationReceiver < ApplicationRecord
  DEFAULT_EMAIL_LABEL = 'Default e-mail'.freeze
  DEFAULT_MUTE_LABEL = 'Do not notify'.freeze
  MAX_RECEIVERS_PER_USER = 50
  DEFAULT_DESCRIPTION_ENABLED = 'Created from the existing mailer setting'.freeze
  DEFAULT_DESCRIPTION_DISABLED = 'Created from the disabled mailer setting'.freeze

  belongs_to :user
  has_many :notification_receiver_actions, -> { order(:id) }, dependent: :delete_all
  has_many :event_routes, dependent: :nullify
  has_many :event_deliveries, dependent: :nullify

  before_validation :set_default_label

  validates :label, presence: true, length: { maximum: 255 }
  validate :check_receiver_limit, on: :create

  def self.ensure_defaults_for!(user)
    return if user.notification_receivers.exists?

    transaction do
      ensure_default_receiver_for!(user)
    end
  end

  def self.ensure_default_receiver_for!(user)
    transaction do
      receiver = default_receiver_for(user) || create_default_receiver!(user)

      if user.mailer_enabled?
        ensure_default_email_action!(receiver)
      end

      ensure_default_route!(user, receiver)
      receiver
    end
  end

  def self.default_description(user)
    if user.mailer_enabled?
      DEFAULT_DESCRIPTION_ENABLED
    else
      DEFAULT_DESCRIPTION_DISABLED
    end
  end

  def self.sync_mailer_enabled!(user)
    transaction do
      ensure_defaults_for!(user)

      receiver = default_receiver_for(user)
      next unless receiver

      receiver.update!(
        label: user.mailer_enabled? ? DEFAULT_EMAIL_LABEL : DEFAULT_MUTE_LABEL,
        description: default_description(user),
        enabled: true,
        mute: !user.mailer_enabled?
      )

      ensure_default_email_action!(receiver) if user.mailer_enabled?
    end
  end

  def self.default_receiver_for(user)
    where(
      user:,
      label: [DEFAULT_EMAIL_LABEL, DEFAULT_MUTE_LABEL],
      description: [
        DEFAULT_DESCRIPTION_ENABLED,
        DEFAULT_DESCRIPTION_DISABLED
      ]
    ).order(:id).first
  end

  def self.create_default_receiver!(user)
    create!(
      user:,
      label: user.mailer_enabled? ? DEFAULT_EMAIL_LABEL : DEFAULT_MUTE_LABEL,
      description: default_description(user),
      mute: !user.mailer_enabled?
    )
  end

  def self.ensure_default_email_action!(receiver)
    receiver.notification_receiver_actions.find_or_create_by!(
      action: 'email',
      target_kind: 'default_recipient'
    ) do |action|
      action.label = DEFAULT_EMAIL_LABEL
    end
  end

  def self.ensure_default_route!(user, receiver)
    route = ::EventRoute.default_route_for(user)

    if route
      route.update!(notification_receiver: receiver)
      return route
    end

    user.event_routes.create!(
      notification_receiver: receiver,
      label: ::EventRoute::DEFAULT_ROUTE_LABEL,
      position: ::EventRoute::DEFAULT_ROUTE_POSITION,
      default_route: true
    )
  end

  def display_action_summary
    return 'Muted' if mute?

    count = notification_receiver_actions.count
    count == 1 ? '1 action' : "#{count} actions"
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
