class NotificationRateLimitState < ApplicationRecord
  belongs_to :user

  validates :delivery_method,
            presence: true,
            inclusion: { in: ->(_) { VpsAdmin::API::Notifications::Actions.names } },
            uniqueness: { scope: :user_id }
end
