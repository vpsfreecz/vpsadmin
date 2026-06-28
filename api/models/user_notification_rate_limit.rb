class UserNotificationRateLimit < ApplicationRecord
  attr_accessor :default_limit_count, :override_limit_count, :used_count,
                :remaining_count, :resets_at, :source

  belongs_to :user

  validates :delivery_method,
            presence: true,
            inclusion: { in: ->(_) { VpsAdmin::API::Notifications::Actions.names } },
            uniqueness: { scope: %i[user_id period] }
  validates :period,
            presence: true,
            inclusion: { in: ->(_) { VpsAdmin::API::Notifications::RateLimits.periods } }
  validates :limit_count, numericality: { only_integer: true, greater_than: 0 }

  def limit_key
    "#{delivery_method}.#{period}"
  end

  def label
    VpsAdmin::API::Notifications::Actions.labels.fetch(delivery_method, delivery_method)
  end

  def period_label
    VpsAdmin::API::Notifications::RateLimits.period_labels.fetch(period, period)
  end

  class << self
    def all_limits_for(user, config: VpsAdmin::API::Notifications::Config.load, now: Time.now)
      overrides = user.user_notification_rate_limits.index_by do |limit|
        [limit.delivery_method, limit.period]
      end

      VpsAdmin::API::Notifications::RateLimits.default_limits(config).flat_map do |delivery_method, periods|
        periods.map do |period, default_limit_count|
          override = overrides[[delivery_method, period]]
          limit_count = override&.limit_count || default_limit_count
          used_count = VpsAdmin::API::Notifications::RateLimits.usage_count(
            user,
            delivery_method,
            period,
            now:
          )

          (override || new(user:, delivery_method:, period:, limit_count:)).tap do |limit|
            limit.limit_count = limit_count
            limit.default_limit_count = default_limit_count
            limit.override_limit_count = override&.limit_count
            limit.used_count = used_count
            limit.remaining_count = [limit_count - used_count, 0].max
            limit.resets_at = VpsAdmin::API::Notifications::RateLimits.next_reset_at(
              user,
              delivery_method,
              period,
              now:
            )
            limit.source = override ? 'override' : 'default'
          end
        end
      end
    end

    def find_limit_for(user, limit_key, config: VpsAdmin::API::Notifications::Config.load, now: Time.now)
      delivery_method, period = parse_limit_key(limit_key)
      all_limits_for(user, config:, now:).find do |limit|
        limit.delivery_method == delivery_method && limit.period == period
      end || raise(ActiveRecord::RecordNotFound)
    end

    def set_limit!(user, limit_key, limit_count)
      delivery_method, period = parse_limit_key(limit_key)
      raise ActiveRecord::RecordNotFound unless VpsAdmin::API::Notifications::Actions.known?(delivery_method)
      raise ActiveRecord::RecordNotFound unless VpsAdmin::API::Notifications::RateLimits.periods.include?(period)

      limit = user.user_notification_rate_limits.find_or_initialize_by(delivery_method:, period:)
      limit.limit_count = limit_count
      limit.save!
      limit
    end

    def parse_limit_key(limit_key)
      delivery_method, period = limit_key.to_s.split('.', 2)
      [delivery_method, period]
    end
  end
end
