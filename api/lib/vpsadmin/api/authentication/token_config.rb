module VpsAdmin::API
  class Authentication::TokenConfig < HaveAPI::Authentication::Token::Config
    request do
      handle do |req, res|
        auth = Operations::Authentication::Password.run(
          req.input[:user],
          req.input[:password],
        )

        if auth.nil? || !auth.authenticated?
          res.error = 'invalid user or password'
          next res
        end

        if auth.complete?
          session = Operations::UserSession::NewTokenLogin.run(
            auth.user,
            req.request,
            req.input[:lifetime],
            req.input[:interval],
          )
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
        auth_token = Operations::Authentication::Totp.run(
          req.input[:token],
          req.input[:code],
        )

        if auth_token
          session = Operations::UserSession::NewTokenLogin.run(
            auth_token.user,
            req.request,
            auth_token.opts['lifetime'],
            auth_token.opts['interval'],
          )
          res.complete = true
          res.token = session.session_token.to_s
          res.valid_to = session.session_token.valid_to
          next res.ok
        else
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
