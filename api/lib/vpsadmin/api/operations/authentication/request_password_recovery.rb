require 'uri'

module VpsAdmin::API
  class Operations::Authentication::RequestPasswordRecovery < Operations::Base
    Account = Struct.new(:recovery, :token, :mail_outcome) do
      def to_mail_hash
        {
          login: recovery.user.login,
          outcome: mail_outcome.to_s,
          reset_url:
        }
      end

      protected

      def auth_url
        (::SysConfig.get(:core, :auth_url) || ::SysConfig.get(:core, :api_url)).to_s.chomp('/')
      end

      def reset_url
        return unless token

        request = recovery.password_recovery_request
        query = {
          client_id: request.oauth2_client&.client_id,
          ui_locales: request.locale
        }.compact.reject { |_, value| value.to_s.empty? }
        suffix = query.empty? ? '' : "?#{URI.encode_www_form(query)}"
        "#{auth_url}/oauth2/password-reset/continue#{suffix}" \
          "#token=#{URI.encode_www_form_component(token)}"
      end
    end

    def run(identifier, locale:, oauth2_client:, request:, submission: nil)
      identifier = identifier.to_s.strip
      return if identifier.empty?

      users, recipient_email = find_users_and_recipient(identifier)
      return if users.empty? || recipient_email.blank?

      account_user_ids = users.map(&:id)
      oauth2_client_id = oauth2_client&.id

      ::PasswordRecoveryRequest.transaction do
        if submission
          submission = ::PasswordRecoverySubmission.where(id: submission.id).lock.take
          return unless submission

          processed = ::PasswordRecoveryRequest.find_by(
            password_recovery_submission_id: submission.id
          )
          return processed if processed
          return if submission.finished_at?
        end

        if oauth2_client_id
          oauth2_client = ::Oauth2Client.where(id: oauth2_client_id).lock.take
          return unless oauth2_client
        end

        locked_users = ::User.including_deleted.where(email: recipient_email)
                             .order(:id)
                             .lock
                             .to_a
        users = locked_users.select { |user| account_user_ids.include?(user.id) }
        return unless users.length == account_user_ids.length

        recovery_request = ::PasswordRecoveryRequest.create!(
          recipient_email:,
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
      outcome, mail_outcome = account_outcomes(user, request)
      token = outcome == :recoverable ? ::PasswordRecovery.generate_token : nil

      recovery = recovery_request.password_recoveries.create!(
        user:,
        outcome:,
        email_snapshot: recipient_email,
        email_token_digest: token && ::PasswordRecovery.digest_token(token),
        email_expires_at: token && (Time.current + ::PasswordRecovery::EMAIL_LIFETIME)
      )

      Account.new(recovery:, token:, mail_outcome:)
    end

    def account_outcomes(user, request)
      policy = Operations::Authentication::PasswordRecoveryPolicy.run(user, request)
      return %i[unavailable administrator] if policy.administrator_account?
      return %i[unavailable unavailable] unless policy.eligible?
      return %i[no_mfa no_mfa] unless policy.effective_mfa?

      %i[recoverable recoverable]
    end

    def client_ip(request)
      request.env['HTTP_CLIENT_IP'] || request.env['HTTP_X_REAL_IP'] || request.ip
    end
  end
end
