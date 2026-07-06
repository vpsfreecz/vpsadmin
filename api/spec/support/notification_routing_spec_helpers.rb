# frozen_string_literal: true

module NotificationRoutingSpecHelpers
  def ensure_default_notification_routing!(user)
    NotificationReceiver.ensure_defaults_for!(user)
  end

  def default_email_receiver_for(user)
    ensure_default_notification_routing!(user)
    NotificationReceiver.default_email_receiver_for(user)
  end

  def default_mute_receiver_for(user)
    ensure_default_notification_routing!(user)
    NotificationReceiver.default_mute_receiver_for(user)
  end

  def route_default_notifications_to_email_for!(user, role: 'account')
    receiver = default_email_receiver_for(user)
    EventRoute.default_route_for(user, role:).update!(notification_receiver: receiver)
    user.set_notification_delivery_method!(:email, true)
    receiver
  end

  def mute_default_notifications_for!(user, role: 'account')
    receiver = default_mute_receiver_for(user)
    EventRoute.default_route_for(user, role:).update!(notification_receiver: receiver)
    user.set_notification_delivery_method!(:email, false)
    receiver
  end
end

RSpec.configure do |config|
  config.include NotificationRoutingSpecHelpers
end
