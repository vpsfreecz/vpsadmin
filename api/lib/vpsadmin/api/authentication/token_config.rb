module VpsAdmin::API
  class Authentication::TokenConfig < HaveAPI::Authentication::Token::Config
    request do
      handle do |req, res|
        auth = Operations::Authentication::Password.run(
          req.input[:user],
          req.input[:password],
          request: req.request,
        )

        if auth.nil? || !auth.authenticated?
          if auth
            Operations::User::FailedLogin.run(
              auth.user,
              :password,
              'invalid password',
              req.request,
            )
          end

          res.error = 'invalid user or password'
          next res
        end

        if auth.complete?
          begin
            session = Operations::UserSession::NewTokenLogin.run(
              auth.user,
              req.request,
              req.input[:lifetime],
              req.input[:interval],
            )
          rescue Exceptions::OperationError => e
            raise Exceptions::AuthenticationError, e.message
          end

          res.complete = true
          res.token = session.session_token.to_s
          res.valid_to = session.session_token.valid_to
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
          req.input[:code],
        )

        if auth.authenticated?
          if auth.used_recovery_code?
            TransactionChains::User::TotpRecoveryCodeUsed.fire(
              auth.user,
              auth.recovery_device,
              req.request,
            )
          end

          begin
            session = Operations::UserSession::NewTokenLogin.run(
              auth.user,
              req.request,
              auth.auth_token.opts['lifetime'],
              auth.auth_token.opts['interval'],
            )
          rescue Exceptions::OperationError => e
            raise Exceptions::AuthenticationError, e.message
          end

          res.complete = true
          res.token = session.session_token.to_s
          res.valid_to = session.session_token.valid_to
          next res.ok
        else
          Operations::User::FailedLogin.run(
            auth.user,
            :totp,
            'invalid totp code',
            req.request,
          )
          res.error = 'invalid totp code'
          next res
        end
      end
    end

    renew do
      handle do |req, res|
        t = ::SessionToken.joins(:token).where(
          user: req.user,
          tokens: {token: req.token},
        ).take

        if t && t.lifetime.start_with?('renewable')
          t.renew!
          res.valid_to = t.valid_to
          res.ok
        else
          res.error = 'unable to renew token'
          res
        end
      end
    end

    revoke do
      handle do |req, res|
        begin
          Operations::UserSession::CloseToken.run(req.user, req.token)
          res.ok
        rescue Exceptions::OperationError
          res.error = 'session not found'
          res
        end
      end
    end

    def find_user_by_token(request, token)
      session = Operations::UserSession::ResumeToken.run(token)
      session && session.user
    end
  end
end
