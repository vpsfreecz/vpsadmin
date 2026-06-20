module VpsAdmin
  HaveAPI.module_name = VpsAdmin::API::Resources
  HaveAPI.implicit_version = '7.0'
  ActiveRecord.schema_format = :ruby

  module API
    module Authentication; end

    module Operations
      module Authentication; end
      module Dataset; end
      module DatasetExpansion; end
      module DnsZone; end
      module DnsServerZone; end
      module DnsTsigKey; end
      module DnsZoneTransfer; end
      module Environment; end
      module Export; end
      module HostIpAddress; end
      module LocationNetwork; end
      module Node; end
      module TotpDevice; end
      module User; end
      module UserSession; end
      module Utils; end
      module Vps; end
    end

    def self.initialize
      DatasetPlans.initialize
    end

    def self.default
      initialize

      WebAuthn.configure do |config|
        config.allowed_origins = [(::SysConfig.get(:core, :auth_url) || ::SysConfig.get(:core, :api_url)).chomp('/')]
        config.rp_name = ::SysConfig.get(:core, :webauthn_rp_name)
      end

      api = HaveAPI::Server.new
      VpsAdmin::API::I18n.configure_server(api)
      api.use_version(:all)
      api.action_state = ActionState

      authenticate(api)

      api.connect_hook(:pre_mount) do |ret, _, sinatra|
        sinatra.get '/metrics' do
          m = Metrics.new
          next [403, VpsAdmin::API::I18n.t('errors.access_denied')] unless m.authenticate(params['access_token'])

          m.compute
          [200, { 'content-type' => 'text/plain' }, m.render]
        end

        sinatra.get '/sd/download-pools' do
          sd = DownloadPoolServiceDiscovery.new(request)
          next [403, VpsAdmin::API::I18n.t('errors.access_denied')] unless sd.authenticate

          [200, { 'content-type' => 'application/json' }, JSON.dump(sd.render)]
        rescue VpsAdmin::API::Exceptions::ConfigurationError => e
          [500, { 'content-type' => 'text/plain' }, e.message]
        end

        webauthn_registration_new = proc do
          if request.get? && (params.has_key?('access_token') || params.has_key?(:access_token))
            halt 400, VpsAdmin::API::I18n.t('errors.access_token_in_url')
          end

          unless authenticated?(settings.api_server.default_version)
            if params[:redirect_uri]
              uri = URI(params[:redirect_uri])
              query_params = URI.decode_www_form(uri.query || '')
              query_params << %w[registerStatus 0]
              query_params << [
                'registerMessage',
                VpsAdmin::API::I18n.t('errors.access_denied_contact_support')
              ]
              uri.query = URI.encode_www_form(query_params)

              redirect uri.to_s
            else
              halt 401, VpsAdmin::API::I18n.t('errors.access_denied')
            end
          end

          access_token = ::UserSession.current&.token&.token
          halt 401, VpsAdmin::API::I18n.t('errors.access_denied') unless access_token

          VpsAdmin::API::Authentication::WebauthnRegister.run(
            current_user,
            params,
            access_token:
          )
        end

        sinatra.get('/webauthn/registration/new', &webauthn_registration_new)
        sinatra.post('/webauthn/registration/new', &webauthn_registration_new)

        ret
      end

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

      api.connect_hook(:description_exception) do |ret, _ctx, e|
        if e.is_a?(::ActiveRecord::RecordNotFound)
          ret[:http_status] = 404
          ret[:message] = VpsAdmin::API::I18n.message('errors.object_not_found')

          # Stop this hook's propagation. If there is ExceptionMailer connected, we
          # don't want it to report this error.
          HaveAPI::Hooks.stop(ret)
        else
          warn "[vpsAdmin API] HaveAPI description failed: #{e.class}: #{e.message}"
          e.backtrace&.each { |line| warn "\t#{line}" }
        end

        ret
      end

      # Scope-based authorization for all actions
      #
      # Each action has its own scope, see the API documentation for their names.
      # Clients decide which scopes they need during authentication. Scopes can
      # also be patterns, e.g. `vps#*` will authorize access to all actions on
      # resource `vps`.
      #
      # Scopes can also match path parameters. For example, `vps#*:vps_id=123`
      # will allow all actions on VPS with ID 123. Multiple path parameters are
      # separated by commas.
      #
      # There is one special scope `all`, which authorizes access to all actions.
      # This is the default for token authentication for backwards compatibility.
      #
      # When no scope is set, access is authorized only to action User.Current,
      # so that the client could get information about the user.
      #
      # Scope syntax:
      #
      #   all
      #   <resource[.<resource...>]>[#<action>][:<param>=<value>[,<param>=<value...>]]
      #
      # resource and action can be patterns, param and value must be exact.
      #
      # Examples:
      #
      #   vps#show                 allow access to single action
      #   vps#show:vps_id=123      allow access to specific VPS
      #   vps#*                    access to all VPS actions
      #   vps#*:vps_id=123         access to all VPS actions, but restricted to a specific ID
      #   vps.feature#*            access to nested resources
      #   {vps,user}#{index,show}  access to VPS and user index/show actions
      HaveAPI::Action.connect_hook(:pre_authorize) do |ret, ctx|
        ret[:blocks] << proc do |u, path_params|
          # Scopes are checked only for authenticated users
          next if u.nil?

          user_session = ::UserSession.current
          raise 'expected user session' if user_session.nil?

          next if user_session.scope == ['all']

          action_scope = ctx.action_scope

          # User.Current is always allowed
          next if action_scope == 'user#current'

          # Check if the user can access this action
          match = user_session.scope.detect do |scope_pattern|
            colon = scope_pattern.index(':')

            if colon
              pattern = scope_pattern[0..(colon - 1)]
              allowed_params = scope_pattern[(colon + 1)..].split(',').to_h do |v|
                arr = v.split('=')

                raise "Invalid path params in scope: #{scope_pattern.inspect}" if arr.length != 2

                arr
              end
            else
              pattern = scope_pattern
            end

            next(false) unless File.fnmatch?(pattern, action_scope)

            if !ctx.doc && allowed_params
              allowed_params.all? do |k, v|
                path_params[k] == v
              end
            else
              true
            end
          end

          deny if match.nil?
        end

        ret
      end

      e = HaveAPI::Extensions::ActionExceptions

      e.rescue(::ActiveRecord::RecordNotFound) do |ret, exception|
        ret[:status] = false
        ret[:http_status] = 404

        ret[:message] = if /find ([^\s]+)[^=]+=(\d+)/ =~ exception.message
                          VpsAdmin::API::I18n.message(
                            'errors.object_with_attribute_not_found',
                            resource: Regexp.last_match(1),
                            id: Regexp.last_match(2)
                          )
                        else
                          VpsAdmin::API::I18n.message('errors.object_not_found_lower')
                        end

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(::ResourceLocked) do |ret, exception|
        ret[:http_status] = 423 # locked
        ret[:status] = false

        lock = exception.get_lock

        ret[:message] = if lock && lock.locked_by.is_a?(::TransactionChain)
                          VpsAdmin::API::I18n.message(
                            'errors.resource_locked_by_transaction_chain',
                            id: lock.locked_by_id,
                            label: lock.locked_by.label
                          )
                        else
                          VpsAdmin::API::I18n.message('errors.resource_locked')
                        end

        puts "[#{Time.now}] Exception ResourceLocked: #{exception.message}"
        puts exception.backtrace.join("\n")

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(VpsAdmin::API::Maintainable::ResourceUnderMaintenance) do |ret, exception|
        ret[:status] = false
        ret[:http_status] = 423
        ret[:message] = VpsAdmin::API::I18n.message(
          'errors.resource_under_maintenance',
          reason: exception.message
        )

        HaveAPI::Hooks.stop(ret)
      end

      e.rescue(VpsAdmin::API::Exceptions::ClusterResourceAllocationError) do |ret, exception|
        ret[:status] = false
        ret[:http_status] = 400
        ret[:message] = VpsAdmin::API::I18n.message(
          'errors.resource_allocation_error',
          reason: exception.message
        )

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

    def self.authenticate(api = nil)
      chain = [
        Authentication::Basic,
        HaveAPI::Authentication::Token.with_config(Authentication::TokenConfig),
        HaveAPI::Authentication::OAuth2.with_config(Authentication::OAuth2Config)
      ]

      if api
        api.auth_chain << chain
      else
        chain
      end
    end

    def self.load_configurable(name)
      path = File.join(root, 'config', "#{name}.rb")
      require_relative path if File.exist?(path)
    end

    def self.configure(&block)
      @configure = block
    end

    def self.root
      return @root if @root

      @root = File.realpath(ENV['VPSADMIN_ROOT'] || File.join(__dir__, '..', '..'))
    end
  end
end
