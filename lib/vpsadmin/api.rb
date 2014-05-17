require_rel 'api/'

module VpsAdmin
  HaveAPI.set_module_name(VpsAdmin::API::Resources)

  module API
    def self.default
      api = HaveAPI::Server.new
      authenticate(api)

      api.use_version(:all)
      api.set_default_version(1)
      api.mount('/')

      api
    end

    def self.custom
      HaveAPI::Server.new
    end

    def self.authenticate(api=nil)
      auth = Proc.new do |request|
        user = nil

        auth = Rack::Auth::Basic::Request.new(request.env)
        if auth.provided? && auth.basic? && auth.credentials
          user = User.authenticate(*auth.credentials)
        end

        User.current = user

        user
      end

      if api
        api.authenticate(&auth)
      else
        auth
      end
    end
  end
end
