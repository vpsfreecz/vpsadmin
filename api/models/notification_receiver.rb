class NotificationReceiver < ApplicationRecord
  DEFAULT_EMAIL_LABEL = 'Default e-mail'.freeze
  DEFAULT_MUTE_LABEL = 'Do not notify'.freeze
  MAX_RECEIVERS_PER_USER = 50

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
      receiver = create!(
        user:,
        label: user.mailer_enabled? ? DEFAULT_EMAIL_LABEL : DEFAULT_MUTE_LABEL,
        description: default_description(user),
        mute: !user.mailer_enabled?
      )

      if user.mailer_enabled?
        receiver.notification_receiver_actions.create!(
          action: 'email',
          target_kind: 'default_recipient',
          label: DEFAULT_EMAIL_LABEL
        )
      end

      user.event_routes.create!(
        notification_receiver: receiver,
        label: EventRoute::DEFAULT_ROUTE_LABEL,
        position: EventRoute::DEFAULT_ROUTE_POSITION
      )
    end
  end

  def self.default_description(user)
    if user.mailer_enabled?
      'Created from the existing mailer setting'
    else
      'Created from the disabled mailer setting'
    end
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
