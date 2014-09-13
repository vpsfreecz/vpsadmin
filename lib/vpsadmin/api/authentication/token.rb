module VpsAdmin::API::Authentication
  class Token < HaveAPI::Authentication::Token::Provider
    protected
    def save_token(request, user, token, lifetime, interval)
      valid = ::ApiToken.create(
          user: user,
          token: token,
          valid_to: (lifetime < 3 ? Time.now + interval : nil),
          lifetime: lifetime,
          interval: interval,
          label: request.user_agent
      ).valid_to

      valid && valid.strftime('%FT%T%z')
    end

    def revoke_token(user, token)
      t = ::ApiToken.find_by(user: user, token: token)
      t && t.destroy
    end

    def renew_token(user, token)
      t = ::ApiToken.find_by(user: user, token: token)

      if t.lifetime.start_with('renewable')
        t.renew
        t.save
        t.valid_to
      end
    end

    def find_user_by_credentials(username, password)
      ::User.authenticate(username, password)
    end

    def find_user_by_token(token)
      t = ::ApiToken.where('token = ? AND ((lifetime = 3 AND valid_to IS NULL) OR valid_to >= ?)', token, Time.now).take

      if t
        ::ApiToken.increment_counter(:use_count, t.id)

        if t.lifetime == 'renewable_auto'
          t.renew
          t.save
        end

        User.current = t.user
      end
    end
  end
end
