module VpsAdmin
  HaveAPI.module_name = VpsAdmin::API::Resources
  HaveAPI.implicit_version = '6.0'
  ActiveRecord::Base.schema_format = :sql

  module API
    module Authentication ; end
    module Operations
      module Authentication ; end
      module Export ; end
      module LocationNetwork ; end
      module TotpDevice ; end
      module User ; end
      module UserSession ; end
      module Utils ; end
    end

    def self.initialize
      DatasetPlans.initialize
    end

    def self.default
      initialize

      api = HaveAPI::Server.new
      api.use_version(:all)
      api.action_state = ActionState

      authenticate(api)

      api.connect_hook(:post_authenticated) do |ret, u|
        # If some user was authenticated in the previous request, but is not now,
        # reset current user info in the per-thread storage.
        if u.nil?
          ::UserSession.current = nil
          ::User.current = nil
        end

        ::PaperTrail.request.whodunnit = u && u.id
        ret
      end

      api.connect_hook(:description_exception) do |ret, ctx, e|
        if e.is_a?(::ActiveRecord::RecordNotFound)
          ret[:http_status] = 404
          ret[:message] = 'Object not found'

          # Stop this hook's propagation. If there is ExceptionMailer connected, we
          # don't want it to report this error.
          HaveAPI::Hooks.stop(ret)
        end

        ret
      end

      e = HaveAPI::Extensions::ActionExceptions

      e.rescue(::ActiveRecord::RecordNotFound) do |ret, exception|
        ret[:status] = false
        ret[:http_status] = 404

        if /find ([^\s]+)[^=]+=(\d+)/ =~ exception.message
          ret[:message] = "object #{$~[1]} = #{$~[2]} not found"
        else
          ret[:message] = "object not found"
        end

        puts "[#{Time.now}] Exception ActiveRecord::RecordNotFound: #{exception.message}"
        puts exception.backtrace.join("\n")

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(::ResourceLocked) do |ret, exception|
        ret[:http_status] = 423 # locked
        ret[:status] = false

        lock = exception.get_lock

        if lock && lock.locked_by.is_a?(::TransactionChain)
          ret[:message] = "Resource is locked by transaction chain "+
                          "#{lock.locked_by_id} (#{lock.locked_by.label}). "+
                          "Try again later."
        else
          ret[:message] = "Resource is locked. Try again later."
        end

        puts "[#{Time.now}] Exception ResourceLocked: #{exception.message}"
        puts exception.backtrace.join("\n")

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(VpsAdmin::API::Maintainable::ResourceUnderMaintenance) do |ret, exception|
        ret[:status] = false
        ret[:http_status] = 423
        ret[:message] = "Resource is under maintenance: #{exception.message}"

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(VpsAdmin::API::Exceptions::ClusterResourceAllocationError) do |ret, exception|
        ret[:status] = false
        ret[:http_status] = 400
        ret[:message] = "Resource allocation error: #{exception.message}"

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(VpsAdmin::API::Exceptions::NotAvailableOnOpenVz) do |ret, exception|
        ret[:http_status] = 500
        ret[:status] = false
        ret[:message] = "This function is not available on OpenVZ Legacy nodes: "+
                        exception.message

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(VpsAdmin::API::Exceptions::OperationNotSupported) do |ret, exception|
        ret[:http_status] = 500
        ret[:status] = false
        ret[:message] = exception.message

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(VpsAdmin::API::Exceptions::ConfigurationError) do |ret, exception|
        ret[:http_status] = 500
        ret[:status] = false
        ret[:message] = exception.message

        HaveAPI::Hooks.stop(ret)
      end

      api.extensions << e

      @configure && @configure.call(api)

      VpsAdmin::API::Plugin::Loader.load('api')

      api.mount('/')

      api
    end

    def self.custom
      HaveAPI::Server.new
    end

    def self.authenticate(api=nil)
      chain = [
        Authentication::Basic,
        HaveAPI::Authentication::Token.with_config(Authentication::TokenConfig),
      ]

      if api
        api.auth_chain << chain
      else
        chain
      end
    end

    def self.load_configurable(name)
      path = File.join(root, 'config', "#{name}.rb")
      require_relative path if File.exists?(path)
    end

    def self.configure(&block)
      @configure = block
    end

    def self.root
      return @root if @root
      @root = File.realpath(File.join(File.dirname(__FILE__), '..', '..'))
    end
  end
end
