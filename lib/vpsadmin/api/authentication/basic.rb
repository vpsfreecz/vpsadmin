module VpsAdmin::API::Authentication
  class Basic < HaveAPI::Authentication::Basic::Provider
    protected
    def find_user(username, password)
      User.current = ::User.authenticate(username, password)
    end
  end
end
