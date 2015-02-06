module VpsAdmin
  HaveAPI.set_module_name(VpsAdmin::API::Resources)

  module API
    module Authentication

    end

    def self.initialize
      DatasetPlans.initialize
    end

    def self.default
      initialize

      api = HaveAPI::Server.new
      api.use_version(:all)
      api.set_default_version(1)

      authenticate(api)

      api.connect_hook(:post_authenticated) do |ret, u|
        ::PaperTrail.whodunnit = u
        ret
      end

      e = HaveAPI::Extensions::ActionExceptions

      e.rescue(::ActiveRecord::RecordNotFound) do |ret, exception|
        ret[:status] = false

        if /find ([^\s]+)[^=]+=(\d+)/ =~ exception.message
          ret[:message] = "object #{$~[1]} = #{$~[2]} not found"
        else
          ret[:message] = "object not found: #{exception.to_s}"
        end

        ret
      end

      e.rescue(::ResourceLocked) do |ret, exception|
        ret[:http_status] = 423 # locked
        ret[:status] = false
        ret[:message] = 'Resource is locked. Try again later.'
        ret
      end

      e.rescue(VpsAdmin::API::Maintainable::ResourceUnderMaintenance) do |ret, exception|
        ret[:status] = false
        ret[:message] = "Resource is under maintenance: #{exception.message}"
        ret
      end

      api.extensions << e

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

    def self.load_configurable(name)
      path = File.join(File.dirname(__FILE__), '..', '..', 'config', "#{name}.rb")
      require_relative path if File.exists?(path)
    end
  end
end
