module VpsAdmin::API
  class Authentication::Basic < HaveAPI::Authentication::Basic::Provider
    protected
    # @return [::UserSession, nil]
    def find_user(request, username, password)
      auth = Operations::Authentication::Password.run(
        username,
        password,
        multi_factor: false,
      )

      if auth.nil? || !auth.authenticated?
        return

      elsif !auth.complete?
        raise Exceptions::AuthenticationError,
              'multi-factor authentication required, use token auth instead'
      end

      Operations::UserSession::NewBasicLogin.run(auth.user, request).user
    end
  end
end
