class PasswordEventCounter < ApplicationRecord
  PASSWORD_CHANGE_SOURCES = %i[
    authenticated
    forced_reset
    recovery
    administrator
    other
  ].freeze

  RECOVERY_SUBMISSION_RESULTS = %i[
    accepted
    rate_limited
    queue_full
  ].freeze

  RECOVERY_QUEUE_CAPACITY_REACHED = :password_recovery_queue_capacity_reached

  EVENT_NAMES = (
    PASSWORD_CHANGE_SOURCES.map { |source| "password_change_#{source}" } +
    RECOVERY_SUBMISSION_RESULTS.map { |result| "password_recovery_submission_#{result}" } +
    [RECOVERY_QUEUE_CAPACITY_REACHED.to_s]
  ).freeze

  validates :name, inclusion: { in: EVENT_NAMES }, uniqueness: true
  validates :event_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  class << self
    def record_password_change!(source, at: Time.current)
      normalized_source = source.to_sym
      unless PASSWORD_CHANGE_SOURCES.include?(normalized_source)
        raise ArgumentError, "unsupported password change source: #{source.inspect}"
      end

      record!("password_change_#{normalized_source}", at:)
    end

    def record_recovery_submission!(result, at: Time.current)
      normalized_result = result.to_sym
      unless RECOVERY_SUBMISSION_RESULTS.include?(normalized_result)
        raise ArgumentError, "unsupported recovery submission result: #{result.inspect}"
      end

      record!("password_recovery_submission_#{normalized_result}", at:)
    end

    def record_recovery_queue_capacity_reached!(at: Time.current)
      record!(RECOVERY_QUEUE_CAPACITY_REACHED, at:)
    end

    def record!(name, at: Time.current)
      normalized_name = name.to_s
      unless EVENT_NAMES.include?(normalized_name)
        raise ArgumentError, "unsupported password event: #{name.inspect}"
      end

      quoted_name = connection.quote(normalized_name)
      quoted_time = connection.quote(at)
      connection.execute(<<~SQL.squish)
        INSERT INTO password_event_counters
          (name, event_count, last_occurred_at, created_at, updated_at)
        VALUES
          (#{quoted_name}, 1, #{quoted_time}, #{quoted_time}, #{quoted_time})
        ON DUPLICATE KEY UPDATE
          event_count = event_count + 1,
          last_occurred_at = IF(
            last_occurred_at IS NULL OR last_occurred_at < VALUES(last_occurred_at),
            VALUES(last_occurred_at),
            last_occurred_at
          ),
          updated_at = VALUES(updated_at)
      SQL

      nil
    end
  end
end
