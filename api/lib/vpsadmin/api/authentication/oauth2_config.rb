require 'erb'

module VpsAdmin::API
  class Authentication::OAuth2Config < HaveAPI::Authentication::OAuth2::Config
    SSO_COOKIE = :vpsadmin_sso

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
          complete: auth.complete? && !auth.reset_password?,
          reset_password: auth.reset_password?,
          auth_token: auth.token,
          user: auth.user,
        )
      end

      # @param auth [Operations::Authentication::Totp::Result]
      # @return [AuthResult]
      def self.from_totp_result(auth)
        new(
          authenticated: auth.authenticated?,
          complete: auth.authenticated? && !auth.reset_password?,
          reset_password: auth.reset_password?,
          auth_token: auth.auth_token.to_s,
          user: auth.user,
        )
      end

      # @return [Boolean]
      attr_reader :authenticated

      # @return [Boolean]
      attr_accessor :complete

      # @return [Boolean]
      attr_reader :cancel

      # @return [String, nil] token used for multi-factor authentication,
      #                       stored as {AuthToken}
      attr_accessor :auth_token

      # @return [User, nil]
      attr_accessor :user

      # @return [Array<String>]
      attr_reader :errors

      # @return [Boolean]
      attr_accessor :reset_password
      alias_method :reset_password?, :reset_password

      # @return [Oauth2Authorization]
      attr_accessor :authorization

      def initialize(authenticated: false, complete: false, auth_token: nil, user: nil, cancel: false, errors: [], reset_password: false)
        @authenticated = authenticated
        @complete = complete
        @auth_token = auth_token
        @user = user
        @cancel = cancel
        @errors = errors
        @reset_password = reset_password
      end
    end

    # @return [AuthResult, nil]
    def handle_get_authorize(sinatra_handler:, sinatra_request:, sinatra_params:, oauth2_request:, oauth2_response:, client:)
      sso = find_sso(sinatra_handler, client)

      if sso
        auth_sso(sso, oauth2_request, oauth2_response, client)
      else
        render_authorize_page(
          oauth2_request:,
          oauth2_response:,
          sinatra_params:,
          client:,
        )
      end
    end

    # @return [AuthResult, nil]
    def handle_post_authorize(sinatra_handler:, sinatra_request:, sinatra_params:, oauth2_request:, oauth2_response:, client:)
      if !sinatra_params[:login]
        return AuthResult.new(cancel: true)
      end

      auth_result =
        if sinatra_params[:user] && sinatra_params[:password]
          auth_credentials(sinatra_request, sinatra_params, oauth2_request, oauth2_response, client)

        elsif sinatra_params[:auth_token] && sinatra_params[:totp_code]
          auth_totp(sinatra_request, sinatra_params, oauth2_request, oauth2_response, client)

        elsif sinatra_params[:auth_token] \
              && sinatra_params[:new_password1] \
              && sinatra_params[:new_password2]
          reset_password(sinatra_request, sinatra_params, oauth2_request, oauth2_response, client)

        else
          nil
        end

      if auth_result.nil? || !auth_result.authenticated || !auth_result.complete
        render_authorize_page(
          oauth2_request:,
          oauth2_response:,
          sinatra_params:,
          client:,
          auth_result:,
        )
      end

      auth_result
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
        authorization.oauth2_client.access_token_lifetime,
        authorization.oauth2_client.access_token_seconds,
        authorization.scope,
      )

      authorization.code.destroy!

      ret = [
        user_session.token.token,
        user_session.token.valid_to,
      ]

      if authorization.oauth2_client.issue_refresh_token
        refresh_token = ::Token.get!(Time.now + authorization.oauth2_client.refresh_token_seconds)
        ret << refresh_token.token
      end

      authorization.update!(
        code: nil,
        user_session: user_session,
        refresh_token: refresh_token,
      )

      ret
    end

    def refresh_tokens(authorization, sinatra_request)
      ::ActiveRecord::Base.transaction do
        authorization.user_session.token.destroy!

        authorization.user_session.refresh_token!(
          authorization.oauth2_client.access_token_lifetime,
          authorization.oauth2_client.access_token_seconds,
        )

        authorization.refresh_token.destroy!

        ret = [
          user_session.token.token,
          user_session.token.valid_to,
        ]

        if authorization.oauth2_client.issue_refresh_token
          authorization.update!(
            refresh_token: ::Token.get!(Time.now + authorization.oauth2_client.refresh_token_seconds)
          )
          ret << authorization.refresh_token.token
        end

        ret
      end
    end

    def handle_post_revoke(sinatra_request, token, token_type_hint: nil)
      # Find access token
      ::Oauth2Authorization
        .joins(user_session: :token)
        .where(tokens: {token: token})
        .each do |auth|
        token = auth.user_session.token
        auth.user_session.update!(token: nil)
        token.destroy!
        auth.close unless auth.refreshable?
        auth.single_sign_on.authorization_revoked(auth) if auth.single_sign_on
        return :revoked
      end

      # Find refresh token
      ::Oauth2Authorization
        .joins(:refresh_token)
        .where(tokens: {token: token})
        .each do |auth|
        refresh_token = auth.refresh_token
        auth.update!(refresh_token: nil)
        refresh_token.destroy!

        if auth.user_session.token.nil?
          auth.user_session.update!(closed_at: Time.now)
        end

        return :revoked
      end

      # Return successfully even when the token wasn't found
      :revoked
    end

    def find_client_by_id(client_id)
      ::Oauth2Client.find_by(client_id: client_id)
    end

    def find_authorization_by_code(client, code)
      ::Oauth2Authorization.joins(:code, :user).where(
        oauth2_client: client,
        tokens: {token: code},
        users: {object_state: %w(active suspended)},
      ).take
    end

    def find_authorization_by_refresh_token(client, refresh_token)
      ::Oauth2Authorization.joins(:refresh_token, :user).where(
        oauth2_client: client,
        tokens: {token: refresh_token},
        users: {object_state: %w(active suspended)},
      ).where(
        'tokens.valid_to > ?', Time.now
      ).take
    end

    def find_user_by_access_token(sinatra_request, access_token)
      session = Operations::UserSession::ResumeOAuth2.run(access_token)
      session && session.user
    end

    def base_url
      ::SysConfig.get(:core, :auth_url) || ::SysConfig.get(:core, :api_url)
    end

    protected
    # @param auth_result [AuthResult]
    def render_authorize_page(oauth2_request:, oauth2_response:, sinatra_params:, client:, auth_result: nil)
      # Variables passed to the ERB template
      auth_token = auth_result && auth_result.auth_token
      user = sinatra_params[:user]
      step =
        if auth_token && !auth_result.reset_password
          :totp
        elsif auth_token && auth_result.reset_password
          :reset_password
        else
          :credentials
        end
      support_mail = ::SysConfig.get(:core, :support_mail)

      @template ||= ERB.new(
        File.read(File.join(__dir__, 'oauth2_authorize.erb')),
        trim_mode: '-',
      )

      oauth2_response.content_type = 'text/html'
      oauth2_response.write(@template.result(binding))
      nil
    end

    def auth_credentials(sinatra_request, sinatra_params, oauth2_request, oauth2_response, client)
      auth = Operations::Authentication::Password.run(
        sinatra_params[:user],
        sinatra_params[:password],
        request: sinatra_request,
      )

      if auth.nil?
        return AuthResult.new(errors: ['invalid user or password'])
      end

      ret = AuthResult.from_password_result(auth)

      unless auth.authenticated?
        Operations::User::FailedLogin.run(
          auth.user,
          :password,
          'invalid password',
          sinatra_request,
        )

        ret.errors << 'invalid user or password'
        return ret
      end

      if auth.authenticated? && auth.complete? && !auth.reset_password?
        create_authorization(ret, oauth2_request, oauth2_response, client)
      end

      ret
    end

    def auth_totp(sinatra_request, sinatra_params, oauth2_request, oauth2_response, client)
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

        unless auth.reset_password?
          create_authorization(ret, oauth2_request, oauth2_response, client)
        end
      else
        Operations::User::FailedLogin.run(
          auth.user,
          :totp,
          'invalid totp code',
          sinatra_request,
        )

        ret.auth_token = sinatra_params[:auth_token]
        ret.errors << 'invalid TOTP code'
      end

      ret
    end

    def reset_password(sinatra_request, sinatra_params, oauth2_request, oauth2_response, client)
      ret = AuthResult.new(
        authenticated: true,
        reset_password: true,
        auth_token: sinatra_params[:auth_token],
      )

      if sinatra_params[:new_password1] != sinatra_params[:new_password2]
        ret.errors << 'passwords do not match'
        return ret
      elsif sinatra_params[:new_password1].length < 8
        ret.errors << 'password should have at least 8 characters'
        return ret
      end

      ret.user = Operations::Authentication::ResetPassword.run(
        sinatra_params[:auth_token],
        sinatra_params[:new_password1],
      )

      ret.auth_token = nil
      ret.complete = true
      ret.reset_password = false

      create_authorization(ret, oauth2_request, oauth2_response, client)

      ret
    end

    def auth_sso(sso, oauth2_request, oauth2_response, client)
      ret = AuthResult.new(
        authenticated: true,
        complete: true,
        user: sso.user,
      )

      create_authorization(ret, oauth2_request, oauth2_response, client, sso: sso)
      ret
    end

    def find_sso(sinatra_handler, client)
      return unless client.allow_single_sign_on

      token = sinatra_handler.cookies[SSO_COOKIE]
      return unless token

      sso = ::SingleSignOn.joins(:token).where(tokens: {token: token}).take
      return if sso.nil? || !sso.usable?

      sso
    end

    def create_authorization(auth_result, oauth2_request, oauth2_response, client, sso: nil)
      now = Time.now
      expires_at = now + 10*60

      ::ActiveRecord::Base.transaction do
        # Create a new single sign on session if applicable
        #
        # We make the SSO valid for as long as the access token would be. Since
        # the access token is not issued at this time (authorization endpoint),
        # we make the SSO longer validity by the amount of time the authorization
        # code is valid for.
        if sso.nil? && client.allow_single_sign_on
          sso = ::SingleSignOn.new(
            user: auth_result.user,
          )

          ::Token.for_new_record!(expires_at + client.access_token_seconds) do |token|
            sso.token = token
            sso
          end

          sso.save!

        # Extend existing single sign on session
        elsif sso
          new_sso_expires_at = expires_at + client.access_token_seconds

          if new_sso_expires_at > sso.token.valid_to
            sso.token.update!(valid_to: new_sso_expires_at)
          end
        end

        # Send single sign on cookie to the client
        if sso
          oauth2_response.set_cookie(SSO_COOKIE, {
            value: sso.token.token,

            # Make the cookie valid for a day. This is to account for renewable_auto
            # tokens that can prolong the session length. We cannot change this
            # cookie's duration after it has been sent, so make it long enough.
            # The token must still be valid, so at worst the user will send
            # an invalid token.
            max_age: 24*60*60,
          })
        end

        authorization = ::Oauth2Authorization.new(
          oauth2_client: client,
          user: auth_result.user,
          scope: oauth2_request.scope,
          code_challenge: oauth2_request.code_challenge,
          code_challenge_method: oauth2_request.code_challenge_method,
          single_sign_on: sso,
        )

        ::Token.for_new_record!(expires_at) do |token|
          authorization.code = token
          authorization.save!
          authorization
        end

        auth_result.authorization = authorization
      end
    end

    def logo_url
      ::SysConfig.get(:core, :logo_url)
    end
  end
end
