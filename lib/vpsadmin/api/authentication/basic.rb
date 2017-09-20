module VpsAdmin::API::Authentication
  class Basic < HaveAPI::Authentication::Basic::Provider
    protected
    def find_user(request, username, password)
      ::UserSession.one_time!(request, username, password)
    end
  end
end
