module VpsAdmin::API::Authentication
  class Token < HaveAPI::Authentication::Token::Provider
    protected
    def save_token(user, token, validity)
      ::ApiToken.create(user: user, token: token, valid_to: Time.new + validity).valid_to
    end

    def revoke_token(user, token)
      t = ::ApiToken.find_by(user: user, token: token)
      t && t.destroy
    end

    def find_user_by_credentials(username, password)
      ::User.authenticate(username, password)
    end

    def find_user_by_token(token)
      t = ::ApiToken.find_by(token: token)

      if t
        ::ApiToken.increment_counter(:use_count, t.id)
        User.current = t.user
      end
    end
  end
end
