require 'digest'

class EmailLoginRateLimit < ApplicationRecord
  SEND_LIMITS = [[900, 5], [86_400, 20]].freeze
  FAILURE_LIMITS = [[900, 10]].freeze

  # An unlocked preliminary check to avoid unnecessary work. The locked check
  # in with_limits remains authoritative when other workers consume the budget.
  def self.available?(user, request, kind)
    limit_windows(user, request, kind).all? do |bucket, window_start, _interval, max|
      (where(bucket:, window_start:).pick(:count) || 0) < max
    end
  end

  # Call under the user lock. All callers acquire bucket locks in the same order.
  def self.with_limits(user, request, kind)
    rows = limit_windows(user, request, kind).map do |bucket, window_start, interval, max|
      insert_all([{ bucket:, window_start:, expires_at: window_start + interval, count: 0 }])
      [where(bucket:, window_start:).lock.take!, max]
    end
    allowed = rows.all? { |row, max| row.count < max }
    consume = yield allowed
    rows.map(&:first).each { |row| row.update!(count: row.count + 1) } if allowed && consume
    allowed
  end

  def self.limit_windows(user, request, kind)
    now = Time.current
    source = request.env['HTTP_X_REAL_IP'].presence || request.ip
    source_key = Digest::SHA256.hexdigest(source.to_s)
    account_limits = kind == :send ? SEND_LIMITS : FAILURE_LIMITS
    limits = account_limits.map { |interval, max| ["#{kind}:user:#{user.id}:#{interval}", interval, max] }
    limits << ["#{kind}:ip:#{source_key}", 900, kind == :send ? 60 : 100]

    limits.sort_by(&:first).map do |bucket, interval, max|
      window_start = Time.at(now.to_i / interval * interval).utc
      [bucket, window_start, interval, max]
    end
  end

  private_class_method :limit_windows
end
