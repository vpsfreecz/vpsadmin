require_rel 'api/'

module VpsAdmin
  HaveAPI.set_module_name(VpsAdmin::API::Resources)

  module API
    module Authentication

    end

    def self.default
      api = HaveAPI::Server.new
      api.use_version(:all)
      api.set_default_version(1)

      authenticate(api)

      api.connect_hook(:post_authenticated) do |u|
        ::PaperTrail.whodunnit = u
      end

      api.mount('/')

      api
    end

    def self.custom
      HaveAPI::Server.new
    end

    def self.authenticate(api=nil)
      chain = [Authentication::Basic, Authentication::Token]

      if api
        api.auth_chain << chain
      else
        chain
      end
    end
  end
end

path = File.join(File.dirname(__FILE__), '..', '..', 'config', 'hooks.rb')
require_relative path if File.exists?(path)
