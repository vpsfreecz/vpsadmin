module VpsAdmin::API::Authentication
  class Token < HaveAPI::Authentication::Token::Provider
    protected
    def generate_token
      ::ApiToken.generate
    end

    def save_token(request, user_session, token, lifetime, interval)
      t = ::ApiToken.create!(
        user: user_session.user,
        token: token,
        valid_to: (lifetime != 'permanent' ? Time.now + interval : nil),
        lifetime: lifetime,
        interval: interval,
        label: request.user_agent,
      )

      ::UserSession.current.start!(t)

      t.valid_to && t.valid_to.strftime('%FT%T%z')
    end

    def revoke_token(request, user, token)
      t = ::ApiToken.find_by(user: user, token: token)
      t && ::UserSession.close!(request, user, token: t)
    end

    def renew_token(request, user, token)
      t = ::ApiToken.find_by(user: user, token: token)

      if t.lifetime.start_with?('renewable')
        t.renew
        t.save!
        t.valid_to
      end
    end

    def find_user_by_credentials(request, username, password)
      ::UserSession.authenticate!(request, username, password)
    end

    def find_user_by_token(request, token)
      t = ::ApiToken.where(
        'token = ? AND ((lifetime = 3 AND valid_to IS NULL) OR valid_to >= ?)',
        token, Time.now
      ).take

      if t
        ::ApiToken.increment_counter(:use_count, t.id)

        if t.lifetime == 'renewable_auto'
          t.renew
          t.save!
        end

        ::UserSession.resume!(request, t.user, token: t)
      end
    end
  end
end
