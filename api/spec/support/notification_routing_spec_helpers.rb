# frozen_string_literal: true

module NotificationRoutingSpecHelpers
  def event_storage_counts
    {
      events: Event.count,
      contexts: EventRoutingContext.count,
      matches: EventRouteMatch.count,
      deliveries: EventDelivery.count,
      attempts: EventDeliveryAttempt.count,
      groups: EventDeliveryGroup.count
    }
  end

  def ensure_default_notification_routing!(user)
    NotificationReceiver.ensure_defaults_for!(user)
  end

  def create_spec_event_route!(user:, event_type: nil,
                               event_type_pattern: nil,
                               subject_scope: :self, label: nil)
    sequence = NotificationReceiver.where(user:).count + 1
    receiver = NotificationReceiver.create!(
      user:,
      label: label || "Spec event receiver #{sequence}"
    )
    receiver.notification_receiver_actions.create!(
      action: :webhook,
      target_kind: :custom,
      target_value: "https://example.test/spec-events/#{user.id}/#{sequence}"
    )

    EventRoute.create!(
      user:,
      notification_receiver: receiver,
      event_type:,
      event_type_pattern:,
      subject_scope:,
      position: EventRoute.where(user:).maximum(:position).to_i + 1
    )
  end

  def create_spec_event_delivery_routes!
    create_spec_event_route!(user: SpecSeed.user)
    create_spec_event_route!(user: SpecSeed.admin)
    create_spec_event_route!(
      user: SpecSeed.admin,
      subject_scope: :visible
    )
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

  config.before(:each, :with_event_delivery) do
    create_spec_event_delivery_routes!
  end
end
