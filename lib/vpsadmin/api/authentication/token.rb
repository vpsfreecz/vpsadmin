module VpsAdmin::API::Authentication
  class Token < HaveAPI::Authentication::Token::Provider
    protected
    def save_token(user, token, validity)
      valid = ::ApiToken.create(
          user: user,
          token: token,
          valid_to: (validity > 0 ? Time.now + validity : nil)
      ).valid_to

      valid && valid.strftime('%FT%T%z')
    end

    def revoke_token(user, token)
      t = ::ApiToken.find_by(user: user, token: token)
      t && t.destroy
    end

    def find_user_by_credentials(username, password)
      ::User.authenticate(username, password)
    end

    def find_user_by_token(token)
      t = ::ApiToken.where('token = ? AND (valid_to IS NULL OR valid_to >= ?)', token, Time.now).take

      if t
        ::ApiToken.increment_counter(:use_count, t.id)
        User.current = t.user
      end
    end
  end
end
