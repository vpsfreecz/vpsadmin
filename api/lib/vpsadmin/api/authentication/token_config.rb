module VpsAdmin::API::Authentication
  class TokenConfig < HaveAPI::Authentication::Token::Config
    request do
      handle do |req, res|
        session = ::UserSession.authenticate!(
          req.request,
          req.input[:user],
          req.input[:password]
        )

        if session.nil?
          res.error = 'bad user or password'
          next(res)
        end

        t = nil

        5.times do
          valid_to =
            if req.input[:lifetime] != 'permanent'
              Time.now + req.input[:interval]
            else
              nil
            end

          t = ::SessionToken.custom(
            user: session.user,
            lifetime: req.input[:lifetime],
            interval: req.input[:interval],
            label: req.request.user_agent,
          )
        end

        if t.nil?
          res.error ='unable to perform login'
          next(res)
        end

        ::UserSession.current.start!(t)

        res.token = t.token_string
        res.valid_to = t.valid_to && t.valid_to.strftime('%FT%T%z')
        res.complete = true
        res.ok
      end
    end

    renew do
      handle do |req, res|
        t = ::SessionToken.joins(:token).where(
          user: req.user,
          tokens: {token: req.token},
        ).take

        if t && t.lifetime.start_with?('renewable')
          t.renew
          t.save!
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
        t = ::SessionToken.joins(:token).where(
          user: req.user,
          tokens: {token: req.token},
        ).take

        if t
          ::UserSession.close!(req.request, req.user, token: t)
          res.ok
        else
          res.error = 'token not found'
          res
        end
      end
    end

    def find_user_by_token(request, token)
      t = ::SessionToken.joins(:token).where(
        'tokens.token = ? AND ((lifetime = 3 AND valid_to IS NULL) OR valid_to >= ?)',
        token, Time.now
      ).take

      if t
        if !%w(active suspended).include?(t.user.object_state)
          t.destroy
          return
        end

        ::SessionToken.increment_counter(:use_count, t.id)

        if t.lifetime == 'renewable_auto'
          t.renew
          t.save!
        end

        ::UserSession.resume!(request, t.user, token: t)
      end
    end
  end
end
