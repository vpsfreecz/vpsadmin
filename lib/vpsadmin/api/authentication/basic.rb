module VpsAdmin::API::Authentication
  class Basic < HaveAPI::Authentication::Basic::Provider
    protected
    def find_user(request, username, password)
      ::User.login(request, username, password)
    end
  end
end
