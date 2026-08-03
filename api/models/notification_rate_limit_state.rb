class NotificationRateLimitState < ApplicationRecord
  belongs_to :user

  validates :delivery_method,
            presence: true,
            inclusion: { in: ->(_) { VpsAdmin::API::Notifications::DeliveryActions.names } },
            uniqueness: { scope: :user_id }
end
