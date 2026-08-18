require 'digest'

module VpsAdmin::API
  class Operations::Authentication::RequestPasswordRecovery < Operations::Base
    THROTTLE_INTERVAL = 10.minutes

    Account = Struct.new(:recovery, :token) do
      def to_mail_hash
        {
          login: recovery.user.login,
          outcome: recovery.outcome,
          reset_url: token && "#{auth_url}/oauth2/password-reset/continue#token=#{token}"
        }
      end

      protected

      def auth_url
        (::SysConfig.get(:core, :auth_url) || ::SysConfig.get(:core, :api_url)).to_s.chomp('/')
      end
    end

    def run(identifier, locale:, oauth2_client:, request:, submission: nil)
      identifier = identifier.to_s.strip
      return if identifier.empty?

      if submission
        processed = ::PasswordRecoveryRequest.find_by(
          password_recovery_submission_id: submission.id
        )
        return processed if processed
      end

      users, recipient_email = find_users_and_recipient(identifier)
      return if users.empty? || recipient_email.blank?

      recipient_digest = digest_recipient(recipient_email)
      account_user_ids = users.map(&:id)

      ::PasswordRecoveryRequest.transaction do
        locked_users = ::User.including_deleted.where(email: recipient_email)
                             .order(:id)
                             .lock
                             .to_a
        users = locked_users.select { |user| account_user_ids.include?(user.id) }
        return unless users.length == account_user_ids.length

        recent = ::PasswordRecoveryRequest.where(recipient_digest:)
                                          .where('created_at > ?', THROTTLE_INTERVAL.ago)
                                          .exists?
        return if recent

        recovery_request = ::PasswordRecoveryRequest.create!(
          recipient_email:,
          recipient_digest:,
          locale: locale.to_s,
          oauth2_client:,
          password_recovery_submission: submission,
          client_ip_addr: client_ip(request),
          user_agent: request.user_agent.to_s
        )

        accounts = users.sort_by(&:login).map do |user|
          create_account(recovery_request, user, recipient_email, request)
        end

        language = ::Language.find_by(code: locale.to_s) ||
                   ::Language.find_by(code: ::MailTemplate::DEFAULT_LANGUAGE_CODE)
        _, mail = ::TransactionChains::PasswordRecoveryMail.fire(
          recovery_request,
          accounts.map(&:to_mail_hash),
          language
        )
        recovery_request.update!(mail_log: mail)
        recovery_request
      end
    end

    protected

    def find_users_and_recipient(identifier)
      by_login = ::User.including_deleted.where(
        'login = ? COLLATE utf8_bin',
        identifier
      ).take

      if by_login
        [[by_login], by_login.email]
      else
        users = ::User.including_deleted.where(email: identifier).to_a
        [users, users.first&.email]
      end
    end

    def create_account(recovery_request, user, recipient_email, request)
      outcome = account_outcome(user, request)
      token = outcome == :recoverable ? ::PasswordRecovery.generate_token : nil

      recovery = recovery_request.password_recoveries.create!(
        user:,
        outcome:,
        email_snapshot: recipient_email,
        email_token_digest: token && ::PasswordRecovery.digest_token(token),
        email_expires_at: token && (Time.current + ::PasswordRecovery::EMAIL_LIFETIME)
      )

      Account.new(recovery:, token:)
    end

    def account_outcome(user, request)
      policy = Operations::Authentication::PasswordRecoveryPolicy.run(user, request)
      return :unavailable unless policy.eligible?
      return :no_mfa unless policy.effective_mfa?

      :recoverable
    end

    def digest_recipient(email)
      Digest::SHA256.hexdigest(email.to_s.strip.downcase)
    end

    def client_ip(request)
      request.env['HTTP_CLIENT_IP'] || request.env['HTTP_X_REAL_IP'] || request.ip
    end
  end
end
