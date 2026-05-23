module VpsAdmin::API
  class Authentication::TokenConfig < HaveAPI::Authentication::Token::Config
    request do
      handle do |req, res|
        auth = Operations::Authentication::Password.run(
          req.input[:user],
          req.input[:password],
          request: req.request
        )

        if auth.nil? || !auth.authenticated?
          if auth
            Operations::User::FailedLogin.run(
              auth.user,
              :password,
              'invalid password',
              req.request
            )
          end

          res.error = 'invalid user or password'
          next res

        elsif !auth.user.enable_token_auth
          res.error = 'token authentication is disabled on this account'
          next res
        end

        if auth.reset_password?
          auth.token.update!(opts: {
                               lifetime: req.input[:lifetime],
                               interval: req.input[:interval],
                               scope: req.input[:scope].split
                             })

          res.complete = false
          res.token = auth.token.to_s
          res.valid_to = auth.token.valid_to
          res.next_action = :reset_password
          next res.ok

        elsif auth.complete?
          begin
            session = Operations::UserSession::NewTokenLogin.run(
              auth.user,
              req.request,
              req.input[:lifetime],
              req.input[:interval],
              req.input[:scope].split
            )
          rescue Exceptions::OperationError => e
            raise Exceptions::AuthenticationError, e.message
          end

          res.complete = true
          res.token = session.token.to_s
          res.valid_to = session.token.valid_to
          next res.ok
        end

        # Multi-factor authentication
        res.complete = false
        res.token = auth.token.to_s
        res.valid_to = auth.token.valid_to
        res.next_action = :totp
        auth.token.update!(opts: {
                             lifetime: req.input[:lifetime],
                             interval: req.input[:interval],
                             scope: req.input[:scope].split
                           })
        res.ok
      end
    end

    action :totp do
      input do
        string :code, label: 'TOTP code', required: true
      end

      handle do |req, res|
        auth = Operations::Authentication::Totp.run(
          req.input[:token],
          req.input[:code]
        )

        if auth.authenticated?
          if auth.used_recovery_code?
            TransactionChains::User::TotpRecoveryCodeUsed.fire(
              auth.user,
              auth.recovery_device,
              req.request
            )
          end

          unless auth.user.enable_token_auth
            res.error = 'token authentication is disabled on this account'
            next res
          end

          if auth.reset_password?
            res.complete = false
            res.token = auth.auth_token.to_s
            res.valid_to = auth.auth_token.valid_to
            res.next_action = :reset_password
            next res.ok
          end

          begin
            session = Operations::UserSession::NewTokenLogin.run(
              auth.user,
              req.request,
              auth.auth_token.opts['lifetime'],
              auth.auth_token.opts['interval'],
              auth.auth_token.opts['scope']
            )
          rescue Exceptions::OperationError => e
            raise Exceptions::AuthenticationError, e.message
          end

          res.complete = true
          res.token = session.token.to_s
          res.valid_to = session.token.valid_to
          next res.ok
        else
          Operations::User::FailedLogin.run(
            auth.user,
            :totp,
            'invalid totp code',
            req.request
          )
          res.error = auth.failure_limit_exceeded? ? 'invalid token' : 'invalid totp code'
          next res
        end
      end
    end

    action :reset_password do
      input do
        password :new_password1, label: 'New password', required: true
        password :new_password2, label: 'Repeat new password', required: true
      end

      handle do |req, res|
        auth_token = ::AuthToken.joins(:token).includes(:token, :user).find_by(
          tokens: { token: req.input[:token] },
          purpose: 'reset_password'
        )

        if auth_token.nil? || !auth_token.token_valid?
          res.error = 'invalid token'
          next res

        elsif !auth_token.user.enable_token_auth
          res.error = 'token authentication is disabled on this account'
          next res

        elsif req.input[:new_password1] != req.input[:new_password2]
          res.error = 'passwords do not match'
          next res

        elsif req.input[:new_password1].length < 8
          res.error = 'password should have at least 8 characters'
          next res
        end

        opts = auth_token.opts || {}
        user = Operations::Authentication::ResetPassword.run(
          auth_token,
          req.input[:new_password1]
        )

        begin
          session = Operations::UserSession::NewTokenLogin.run(
            user,
            req.request,
            opts.fetch('lifetime', 'fixed'),
            opts.fetch('interval', 5 * 60),
            opts.fetch('scope', ['all'])
          )
        rescue Exceptions::OperationError => e
          raise Exceptions::AuthenticationError, e.message
        end

        res.complete = true
        res.token = session.token.to_s
        res.valid_to = session.token.valid_to
        res.ok
      end
    end

    renew do
      handle do |req, res|
        user_session = ::UserSession.joins(:token).where(
          auth_type: :token,
          user: req.user,
          tokens: { token: req.token }
        ).take

        if user_session && user_session.token_lifetime.start_with?('renewable')
          user_session.renew_token!
          res.valid_to = user_session.token.valid_to
          res.ok
        else
          res.error = 'unable to renew token'
          res
        end
      end
    end

    revoke do
      handle do |req, res|
        Operations::UserSession::CloseToken.run(req.user, req.token)
        res.ok
      rescue Exceptions::OperationError
        res.error = 'session not found'
        res
      end
    end

    def find_user_by_token(_request, token)
      session = Operations::UserSession::ResumeToken.run(token)
      return if !session || !session.user || !session.user.enable_token_auth

      session.user
    end
  end
end
