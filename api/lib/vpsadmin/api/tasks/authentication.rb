module VpsAdmin::API::Tasks
  class Authentication < Base
    # Close expired authentication processes
    #
    # Accepts the following environment variables:
    # [EXECUTE]: The authentication processes are closed only when set to 'yes'
    def close_expired
      ::AuthToken.joins(:token).includes(:token).where(
        'tokens.valid_to IS NOT NULL AND tokens.valid_to < ?',
        Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      ).each do |t|
        puts "Token ##{t.id} valid_to=#{t.valid_to} token=#{t}"
        next if ENV['EXECUTE'] != 'yes'

        ActiveRecord::Base.transaction do
          VpsAdmin::API::Operations::User::IncompleteLogin.run(
            t,
            :totp,
            'authentication token expired'
          )
          t.destroy!
        end
      end

      ::Oauth2Authorization
        .joins(:code)
        .where(user_session: nil)
        .where('tokens.valid_to < ?', Time.now)
        .each do |auth|
        puts "OAuth2 authorization #{auth.id} valid_to=#{auth.code.valid_to} code=#{auth.code.token}"
        next if ENV['EXECUTE'] != 'yes'

        auth.destroy!
      end

      ::WebauthnChallenge
        .joins(:token)
        .where('tokens.valid_to < ?', Time.now)
        .each do |challenge|
        puts "WebAuthn challenge ##{challenge.id} valid_to=#{challenge.valid_to}"
        next if ENV['EXECUTE'] != 'yes'

        ActiveRecord::Base.transaction do
          if challenge.challenge_type == 'authentication' && challenge.password_recovery_id.nil?
            VpsAdmin::API::Operations::User::IncompleteLogin.run(
              challenge,
              :webauthn,
              'authentication challenge expired'
            )
          end

          challenge.destroy!
        end
      end

      expired_recoveries = ::PasswordRecovery.active.where(
        '(email_consumed_at IS NULL AND email_expires_at < :now) OR ' \
        '(email_consumed_at IS NOT NULL AND session_expires_at < :now)',
        now: Time.current
      )
      expired_recoveries.each do |recovery|
        puts "Password recovery ##{recovery.id} expired"
      end
      if ENV['EXECUTE'] == 'yes'
        expired_recoveries.update_all(invalidated_at: Time.current)
      end

      stale_requests = ::PasswordRecoveryRequest.where(
        'created_at < ?',
        ::PasswordRecovery::RECORD_RETENTION.ago
      )
      stale_requests.each do |recovery_request|
        puts "Password recovery request ##{recovery_request.id} is stale"
        recovery_request.destroy! if ENV['EXECUTE'] == 'yes'
      end

      submissions_before = ::PasswordRecoverySubmission::RECORD_RETENTION.ago
      stale_submissions = ::PasswordRecoverySubmission.where('created_at < ?', submissions_before)
      stale_submissions.each do |submission|
        puts "Password recovery submission ##{submission.id} is stale"
      end
      return unless ENV['EXECUTE'] == 'yes'

      ::PasswordRecoverySubmission.destroy_stale!(before: submissions_before)
    end

    # Email users about failed login attempts
    #
    # Accepts the following environment variables:
    # [EXECUTE]: The authentication processes are closed only when set to 'yes'
    def report_failed_logins
      users = {}

      ::UserFailedLogin
        .includes(:user)
        .where(reported_at: nil)
        .order('user_id, created_at')
        .each do |login|
        users[login.user] ||= []
        users[login.user] << login
      end

      user_attempt_groups =
        users.transform_values do |logins|
          attempts = {}

          logins.each do |login|
            k = [
              login.auth_type,
              login.reason,
              login.client_ip_addr,
              login.user_agent_id
            ].join('-')

            attempts[k] ||= []
            attempts[k] << login
          end

          attempts.values
        end

      user_attempt_groups.each do |user, attempt_groups|
        puts "User #{user.id}: #{attempt_groups.inject(0) { |acc, grp| acc + grp.length }} failed attempts"
      end

      return if user_attempt_groups.empty? || ENV['EXECUTE'] != 'yes'

      TransactionChains::User::ReportFailedLogins.fire2(args: [user_attempt_groups])
    end
  end
end
