module VpsAdmin::API
  # Aggregate the current daily report without retaining credential or client data.
  class DailyReportAuthentication
    AUTH_TYPES = %w[basic token oauth2].freeze

    def initialize(from:, to:)
      @from = from
      @to = to
    end

    def vars
      changes = password_changes

      {
        user_sessions: user_sessions,
        password_changes: changes,
        password_recoveries: password_recoveries(changes[:by_source].fetch('recovery')),
        failed_logins: failed_logins
      }
    end

    protected

    def during(relation, column = :created_at)
      relation.where(column => @from...@to)
    end

    def counts(relation, user_column: 'user_id')
      total, users = relation.pick(Arel.sql('COUNT(*)'), Arel.sql("COUNT(DISTINCT #{user_column})"))
      { total: total.to_i, users: users.to_i }
    end

    def session_counts(relation)
      groups = relation.group(:auth_type).pluck(
        :auth_type, Arel.sql('COUNT(*)'), Arel.sql('COUNT(DISTINCT user_sessions.user_id)')
      )
      by_auth_type = AUTH_TYPES.to_h { |type| [type, { total: 0, users: 0 }] }
      groups.each { |type, total, users| by_auth_type[type] = { total: total.to_i, users: users.to_i } }

      counts(relation, user_column: 'user_sessions.user_id').merge(by_auth_type:)
    end

    def user_sessions
      active = active_sessions

      {
        created: session_counts(during(::UserSession.all)),
        active: session_counts(active),
        permanent: counts(active.where(token_lifetime: :permanent), user_column: 'user_sessions.user_id'),
        administrator_created: counts(active.where.not(admin_id: nil), user_column: 'user_sessions.user_id')
      }
    end

    def active_sessions
      # Match ResumeToken/ResumeOAuth2 and their providers, including the OAuth2
      # refresh path. A missing access token can still have a usable refresh token.
      # Keep this reporting projection aligned when those authentication rules
      # change; cleanup and the public open-session filter have narrower semantics.
      ::UserSession.joins(:user)
                   .where(closed_at: nil)
                   .where('user_sessions.created_at < ?', @to)
                   .where(users: { object_state: %w[active suspended], lockout: false, password_reset: false })
                   .where(<<~SQL.squish)
                     (user_sessions.auth_type = 'token' AND users.enable_token_auth = TRUE)
                     OR (user_sessions.auth_type = 'oauth2' AND users.enable_oauth2_auth = TRUE)
                   SQL
                   .where(<<~SQL.squish, now: @to)
                     EXISTS (
                       SELECT 1 FROM tokens
                       WHERE tokens.id = user_sessions.token_id
                         AND ((user_sessions.token_lifetime = 3 AND tokens.valid_to IS NULL)
                              OR tokens.valid_to >= :now)
                     ) OR (
                       user_sessions.auth_type = 'oauth2' AND EXISTS (
                         SELECT 1 FROM oauth2_authorizations
                         INNER JOIN tokens ON tokens.id = oauth2_authorizations.refresh_token_id
                         WHERE oauth2_authorizations.user_session_id = user_sessions.id
                           AND tokens.valid_to > :now
                       )
                     )
                   SQL
    end

    def password_changes
      grouped = during(::PasswordChangeLog.all).group(:source).count
      by_source = PasswordChanges::SOURCES.to_h { |source| [source.to_s, 0] }.merge(grouped)
      { total: by_source.values.sum, by_source: }
    end

    def password_recoveries(completed)
      all = ::PasswordRecovery.where('created_at < ?', @to)
      recoverable = all.recoverable.where('completed_at IS NULL OR completed_at > ?', @to)
      # Once the email link is consumed, the session deadline replaces its expiry.
      # Unlike the live model predicates, this projection uses one report cutoff
      # and gives completed recoveries precedence over their invalidation.
      # Recheck these boundaries when recovery or cleanup rules change.
      deadline = <<~SQL.squish
        CASE WHEN email_consumed_at IS NULL OR email_consumed_at > #{::PasswordRecovery.connection.quote(@to)}
          THEN email_expires_at ELSE session_expires_at END
      SQL
      expired = recoverable
                .where("(#{deadline}) >= :start AND (#{deadline}) < :end", start: @from, end: @to)
                .where("invalidated_at IS NULL OR invalidated_at >= (#{deadline})")
                .count
      invalidated = during(recoverable, :invalidated_at)
                    .where("invalidated_at < (#{deadline})")
                    .count
      pending = recoverable.where('invalidated_at IS NULL OR invalidated_at > ?', @to)
                           .where("(#{deadline}) > ?", @to)
      pending_email = pending.where('email_consumed_at IS NULL OR email_consumed_at > ?', @to).count
      pending_session = pending.where('email_consumed_at <= ?', @to).count

      {
        requests: during(::PasswordRecoveryRequest.all).count,
        started: during(all.recoverable).count,
        completed:,
        unfulfilled: expired + invalidated,
        expired:,
        invalidated:,
        no_mfa: during(all.no_mfa).count,
        unavailable: during(all.unavailable).count,
        pending: { total: pending_email + pending_session, email: pending_email, session: pending_session }
      }
    end

    def failed_logins
      relation = during(::UserFailedLogin.all)
      rows = relation.group(:auth_type, :reason).order(:auth_type, :reason).pluck(
        :auth_type, :reason, Arel.sql('COUNT(*)'), Arel.sql('COUNT(DISTINCT user_id)')
      )
      counts(relation).merge(
        by_reason: rows.map do |type, reason, total, users|
          { auth_type: type, reason:, total: total.to_i, users: users.to_i }
        end
      )
    end
  end
end
