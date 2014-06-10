module VpsAdmin::API::Authentication
  class Token < HaveAPI::Authentication::Token::Provider
    protected
    def save_token(user, token, validity)

    end

    def revoke_token(user, token)

    end

    def find_user_by_credentials(username, password)

    end

    def find_user_by_token(token)

    end
  end
end
