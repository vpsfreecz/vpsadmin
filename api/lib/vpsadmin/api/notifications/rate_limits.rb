module VpsAdmin::API::Notifications
  module RateLimits
    PERIODS = {
      'minute' => 60,
      'hour' => 60 * 60,
      'day' => 24 * 60 * 60,
      'week' => 7 * 24 * 60 * 60
    }.freeze
    PERIOD_LABELS = {
      'minute' => 'minute',
      'hour' => 'hour',
      'day' => 'day',
      'week' => 'week'
    }.freeze

    module_function

    def periods
      PERIODS.keys
    end

    def period_labels
      PERIOD_LABELS
    end

    def default_limits(config = Config.load)
      configured = rate_limit_config(config).fetch('defaults', {})
      defaults = deep_dup(DeliveryActions.default_rate_limits)

      configured.each do |delivery_method, periods|
        delivery_method = delivery_method.to_s
        next unless defaults.has_key?(delivery_method)
        next unless periods.is_a?(Hash)

        periods.each do |period, count|
          period = period.to_s
          next unless PERIODS.has_key?(period)

          value = Integer(count)
          defaults[delivery_method][period] = value if value > 0
        rescue ArgumentError, TypeError
          next
        end
      end

      defaults
    end

    def limit_count(user, delivery_method, period, config: Config.load)
      delivery_method = delivery_method.to_s
      period = period.to_s

      override = user.user_notification_rate_limits.find_by(
        delivery_method:,
        period:
      )
      override&.limit_count || default_limits(config).dig(delivery_method, period)
    end

    def rate_limited_until(delivery, config: Config.load, now: Time.now)
      with_limit_lock(delivery) do
        rate_limited_until_without_lock(delivery, config:, now:)
      end
    end

    def with_limit_lock(delivery, &)
      user = delivery.recipient_user
      return yield unless user

      state = state_for(user, delivery.action)

      state.with_lock(&)
    end

    def rate_limited_until_without_lock(delivery, config: Config.load, now: Time.now)
      user = delivery.recipient_user
      return unless user

      limited_until = periods.filter_map do |period|
        limited_until_for(user, delivery.action, period, config:, now:)
      end.max

      limited_until if limited_until && limited_until > now
    end

    def usage_count(user, delivery_method, period, now: Time.now)
      seconds = PERIODS.fetch(period.to_s)
      ::EventDeliveryAttempt
        .where(
          recipient_user_id: user.id,
          action: delivery_method.to_s,
          started_at: (now - seconds)..now
        )
        .count
    end

    def next_reset_at(user, delivery_method, period, now: Time.now)
      seconds = PERIODS.fetch(period.to_s)
      started_at = ::EventDeliveryAttempt
                   .where(
                     recipient_user_id: user.id,
                     action: delivery_method.to_s,
                     started_at: (now - seconds)..now
                   )
                   .order(:started_at)
                   .limit(1)
                   .pluck(:started_at)
                   .first
      started_at && (started_at + seconds)
    end

    def limited_until_for(user, delivery_method, period, config:, now:)
      limit = limit_count(user, delivery_method, period, config:)
      return unless limit

      count = usage_count(user, delivery_method, period, now:)
      return if count < limit

      reset_after_attempts = count - limit
      reset_started_at = attempts_in_window(user, delivery_method, period, now:)
                         .offset(reset_after_attempts)
                         .limit(1)
                         .pluck(:started_at)
                         .first
      reset_started_at && (reset_started_at + PERIODS.fetch(period.to_s))
    end

    def attempts_in_window(user, delivery_method, period, now:)
      seconds = PERIODS.fetch(period.to_s)
      ::EventDeliveryAttempt
        .where(
          recipient_user_id: user.id,
          action: delivery_method.to_s,
          started_at: (now - seconds)..now
        )
        .order(:started_at)
    end

    def state_for(user, delivery_method)
      ::NotificationRateLimitState.find_or_create_by!(
        user:,
        delivery_method: delivery_method.to_s
      )
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def rate_limit_config(config)
      config.fetch('rate_limits', {})
    end

    def deep_dup(value)
      Marshal.load(Marshal.dump(value))
    end
  end

  class DomainRateLimiter
    def initialize(interval:, clock:, sleeper:)
      @interval = interval
      @clock = clock
      @sleeper = sleeper
      @next_available_at = {}
      @mutex = Mutex.new
    end

    def wait(domains)
      loop do
        delay = reserve_or_delay(domains)
        return unless delay > 0

        @sleeper.call(delay)
      end
    end

    def delay_for(domains)
      keys = domain_keys(domains)
      return 0 if keys.empty? || @interval <= 0

      @mutex.synchronize do
        delay_for_keys(keys, @clock.call)
      end
    end

    def reserve_or_delay(domains)
      keys = domain_keys(domains)
      return 0 if keys.empty? || @interval <= 0

      @mutex.synchronize do
        now = @clock.call
        delay = delay_for_keys(keys, now)

        if delay <= 0
          reserved_until = now + @interval
          keys.each { |key| @next_available_at[key] = reserved_until }
          return 0
        end

        delay
      end
    end

    protected

    def domain_keys(domains)
      Array(domains).map(&:to_s).reject(&:blank?).uniq.sort
    end

    def delay_for_keys(keys, now)
      available_at = keys.map { |key| @next_available_at.fetch(key, now) }.max
      available_at - now
    end
  end
end
