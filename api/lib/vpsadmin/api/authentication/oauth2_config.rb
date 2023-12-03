require 'erb'

module VpsAdmin::API
  class Authentication::OAuth2Config < HaveAPI::Authentication::OAuth2::Config
    ACCESS_TOKEN_LIFETIME = 15*60

    REFRESH_TOKEN_LIFETIME = 24*60*60

    # Authentication result passed back to HaveAPI OAuth2 provider
    #
    # See {HaveAPI::Authentication::OAuth2::AuthResult} for the interface we're
    # implementing.
    class AuthResult
      # @param auth [Operations::Authentication::Password::Result]
      # @return [AuthResult]
      def self.from_password_result(auth)
        new(
          authenticated: auth.authenticated?,
          complete: auth.complete?,
          token: auth.token,
          user: auth.user,
        )
      end

      # @param auth [Operations::Authentication::Totp::Result]
      # @return [AuthResult]
      def self.from_totp_result(auth)
        new(
          authenticated: auth.authenticated?,
          complete: auth.authenticated?,
          user: auth.user,
        )
      end

      # @return [Boolean]
      attr_reader :authenticated

      # @return [Boolean]
      attr_reader :complete

      # @return [Boolean]
      attr_reader :cancel

      # @return [String, nil] token used for multi-factor authentication,
      #                       stored as {AuthToken}
      attr_accessor :token

      # @return [User, nil]
      attr_reader :user

      # @return [Array<String>]
      attr_reader :errors

      # @return [Oauth2Authorization]
      attr_accessor :authorization

      def initialize(authenticated: false, complete: false, token: nil, user: nil, cancel: false, errors: [])
        @authenticated = authenticated
        @complete = complete
        @token = token
        @user = user
        @cancel = cancel
        @errors = errors
      end
    end

    # @param auth_result [AuthResult]
    def render_authorize_page(oauth2_request, sinatra_params, client, auth_result: nil)
      auth_token = auth_result && auth_result.token

      @template ||= ERB.new(
        File.read(File.join(__dir__, 'oauth2_authorize.erb')),
        trim_mode: '-',
      )
      @template.result(binding)
    end

    # @return [AuthResult, nil]
    def handle_post_authorize(sinatra_request, sinatra_params, oauth2_request, client)
      if !sinatra_params[:login]
        return AuthResult.new(cancel: true)
      end

      if sinatra_params[:user] && sinatra_params[:password]
        auth_credentials(sinatra_request, sinatra_params, oauth2_request, client)

      elsif sinatra_params[:auth_token] && sinatra_params[:totp_code]
        auth_totp(sinatra_request, sinatra_params, oauth2_request, client)

      else
        nil
      end
    end

    # @param auth_result [AuthResult]
    def get_authorization_code(auth_result)
      auth_result.authorization.code.token
    end

    # @param authorization [Oauth2Authorization]
    def get_tokens(authorization, sinatra_request)
      user_session = Operations::UserSession::NewOAuth2Login.run(
        authorization.user,
        sinatra_request,
        ACCESS_TOKEN_LIFETIME,
      )

      authorization.code.destroy!

      authorization.update!(
        code: nil,
        user_session: user_session,
        refresh_token: ::Token.get!(Time.now + REFRESH_TOKEN_LIFETIME),
      )

      [
        user_session.session_token.token.token,
        user_session.session_token.token.valid_to,
        authorization.refresh_token.token,
      ]
    end

    def refresh_tokens(authorization, sinatra_request)
      ::ActiveRecord::Base.transaction do
        authorization.user_session.session_token.destroy!

        authorization.user_session.update!(
          session_token: ::SessionToken.custom!(
            user: user,
            lifetime: 'fixed',
            interval: ACCESS_TOKEN_LIFETIME,
            label: sinatra_request.user_agent,
          ),
        )

        authorization.refresh_token.destroy!

        authorization.update!(
          refresh_token: ::Token.get!(Time.now + REFRESH_TOKEN_LIFETIME)
        )

        [
          user_session.session_token.token.token,
          user_session.session_token.token.valid_to,
          authorization.refresh_token.token,
        ]
      end
    end

    def find_client_by_id(client_id)
      ::Oauth2Client.find_by(client_id: client_id)
    end

    def find_authorization_by_code(client, code)
      ::Oauth2Authorization.joins(:code).where(
        oauth2_client: client,
        tokens: {token: code},
      ).take
    end

    def find_authorization_by_refresh_token(client, refresh_token)
      ::Oauth2Authorization.joins(:refresh_token).where(
        oauth2_client: client,
        tokens: {token: refresh_token},
      ).where(
        'tokens.valid_to > ?', Time.now
      ).take
    end

    def find_user_by_access_token(sinatra_request, access_token)
      session = Operations::UserSession::ResumeOAuth2.run(access_token)
      session && session.user
    end

    protected
    def auth_credentials(sinatra_request, sinatra_params, oauth2_request, client)
      auth = Operations::Authentication::Password.run(
        sinatra_params[:user],
        sinatra_params[:password],
        request: sinatra_request,
      )

      if auth.nil?
        return AuthResult.new(errors: ['invalid user or password'])
      end

      ret = AuthResult.from_password_result(auth)

      if !auth.authenticated?
        Operations::User::FailedLogin.run(
          auth.user,
          :password,
          'invalid password',
          sinatra_request,
        )

        ret.errors << 'invalid user or password'
      end

      if auth.authenticated? && auth.complete?
        create_authorization(ret, oauth2_request, client)
      end

      ret
    end

    def auth_totp(sinatra_request, sinatra_params, oauth2_request, client)
      auth = Operations::Authentication::Totp.run(
        sinatra_params[:auth_token],
        sinatra_params[:totp_code],
      )

      ret = AuthResult.from_totp_result(auth)

      if auth.authenticated?
        if auth.used_recovery_code?
          TransactionChains::User::TotpRecoveryCodeUsed.fire(
            auth.user,
            auth.recovery_device,
            sinatra_request,
          )
        end

        create_authorization(ret, oauth2_request, client)
      else
        Operations::User::FailedLogin.run(
          auth.user,
          :totp,
          'invalid totp code',
          sinatra_request,
        )

        ret.token = sinatra_params[:auth_token]
        ret.errors << 'invalid TOTP code'
      end

      ret
    end

    def create_authorization(auth_result, oauth2_request, client)
      expires_at = Time.now + 10*60

      authorization = ::Oauth2Authorization.new(
        oauth2_client: client,
        user: auth_result.user,
        scope: oauth2_request.scope,
        code_challenge: oauth2_request.code_challenge,
        code_challenge_method: oauth2_request.code_challenge_method,
      )

      ::Token.for_new_record!(expires_at) do |token|
        authorization.code = token
        authorization.save!
        authorization
      end

      auth_result.authorization = authorization
    end

    def logo_url
      ::SysConfig.get(:core, :logo_url)
    end
  end
end
