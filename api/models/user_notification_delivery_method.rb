class UserNotificationDeliveryMethod < ApplicationRecord
  DEFAULT_ENABLED = true

  belongs_to :user

  validates :delivery_method, presence: true,
                              inclusion: { in: ->(_) { delivery_methods } },
                              uniqueness: { scope: :user_id }
  validates :enabled, inclusion: { in: [true, false] }

  def label
    VpsAdmin::API::Notifications::Actions.labels.fetch(delivery_method, delivery_method)
  end

  class << self
    def delivery_methods
      VpsAdmin::API::Notifications::Actions.names
    end

    def all_methods_for(user)
      settings = user.user_notification_delivery_methods.index_by(&:delivery_method)

      delivery_methods.map do |delivery_method|
        settings[delivery_method] ||
          new(
            user:,
            delivery_method:,
            enabled: default_enabled?(delivery_method)
          )
      end
    end

    def known_delivery_method?(delivery_method)
      VpsAdmin::API::Notifications::Actions.known?(normalize_delivery_method(delivery_method))
    end

    def normalize_delivery_method(delivery_method)
      delivery_method.to_s
    end

    def default_enabled?(_delivery_method)
      DEFAULT_ENABLED
    end
  end
end
