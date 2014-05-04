module VpsAdmin
  module API
    # Return a list of all resources or yield them if block is given.
    def self.resources # yields: resource
      ret = []

      Resources.constants.select do |c|
        obj = Resources.const_get(c)

        if obj.obj_type == :resource
          if block_given?
            yield obj
          else
            ret << obj
          end
        end
      end

      ret
    end

    # Iterate through all resources and return those for which yielded block
    # returned true.
    def self.filter_resources
      ret = []

      resources do |r|
        ret << r if yield(r)
      end

      ret
    end

    # Return list of resources for version +v+.
    def self.get_version_resources(v)
      filter_resources do |r|
        r.version.is_a?(Array) ? r.version.include?(v) : r.version == v
      end
    end

    # Return a list of all API versions.
    def self.get_versions
      ret = []

      resources do |r|
        ret << r.version unless ret.include?(r.version)
      end

      ret
    end

    # Include specific version +v+ of API.
    # +v+ can be one of:
    # [:all]     use all available versions
    # [Array]    use all versions in +Array+
    # [version]  include only concrete version
    # +default+ is set only when including concrete version. Use
    # set_default_version otherwise.
    def self.use_version(v, default: false)
      App.versions ||= []

      if v == :all
        App.versions = get_versions
      elsif v.is_a?(Array)
        App.versions += v
        App.versions.uniq!
      else
        App.versions << v
        App.default_version = v if default
      end
    end

    # Set default version of API.
    def self.set_default_version(v)
      App.default_version = v
    end

    # Load routes for all resource from included API versions.
    # All routes are mounted under prefix +path+.
    # If no default version is set, the last included version is used.
    def self.mount(path)
      App.mount(path)
    end

    # Start API.
    def self.start!
      ActiveRecord::Base.establish_connection(
          adapter:  'mysql',
          host:     'localhost',
          username: 'vpsadmin2',
          password: 'rails',
          database: 'vpsadmin2'
      )
      
      App.start!
    end

    class App < Sinatra::Base
      set :views, settings.root + '/views'
      set :bind, '0.0.0.0'

      helpers do
        def authenticate!
          unless authenticated?
            report_error(401, {'WWW-Authenticate' => 'Basic realm="Restricted Area"'},
                         'Action requires user to authenticate')
          end
        end

        def authenticated?
          auth = Rack::Auth::Basic::Request.new(request.env)
          if auth.provided? && auth.basic? && auth.credentials
            @current_user = User.authenticate(*auth.credentials)
          end

          @current_user
        end

        def current_user
          @current_user
        end

        def pretty_format(obj)
          ret = ''
          PP.pp(obj, ret)
        end

        def report_error(code, headers, msg)
          halt code, headers, JSON.pretty_generate({
            status: false,
            response: nil,
            message: msg
          })
        end
      end

      not_found do
        report_error(404, {}, 'Action not found')
      end

      after do
        ActiveRecord::Base.clear_active_connections!
      end

      class << self
        attr_accessor :versions, :default_version, :root, :routes

        def mount(prefix='/')
          @root = prefix
          @routes = {}

          # Mount root
          get @root do
            @api = App.describe
            erb :index
          end

          options @root do
            JSON.pretty_generate(App.describe)
          end

          @default_version ||= versions.last

          # Mount default version first
          mount_version(@root, @default_version)

          @versions.each do |v|
            mount_version(version_prefix(v), v)
          end
        end

        def mount_version(prefix, v)
          @routes[v] = {}

          get prefix do
            @v = v
            @help = App.describe_version(v)
            erb :version
          end

          options prefix do
            JSON.pretty_generate(App.describe_version(v))
          end

          API.get_version_resources(v).each do |resource|
            @routes[v][resource] = {resources: {}, actions: {}}

            resource.routes(prefix).each do |route|
              if route.is_a?(Hash)
                @routes[v][resource][:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

              else
                @routes[v][resource][:actions][route.action] = route.url
                mount_action(v, route)
              end
            end
          end
        end

        def mount_nested_resource(v, routes)
          ret = {resources: {}, actions: {}}

          routes.each do |route|
            if route.is_a?(Hash)
              ret[:resources][route.keys.first] = mount_nested_resource(v, route.values.first)

            else
              ret[:actions][route.action] = route.url
              mount_action(v, route)
            end
          end

          ret
        end

        def mount_action(v, route)
          self.method(route.http_method).call(route.url) do
            authenticate! if route.action.auth

            request.body.rewind

            begin
              body = JSON.parse(request.body.read, symbolize_names: true)
            rescue => e
              report_error(400, {}, 'Bad JSON syntax')
            end

            action = route.action.new(v, params, body)

            unless action.authorized?(current_user)
              halt 403, "you ain't supposed to be here"
            end

            status, reply, errors = action.safe_exec
            reply = {
                status: status,
                response: status ? reply : nil,
                message: !status ? reply : nil,
                errors: errors
            }

            JSON.pretty_generate(reply)
          end

          options route.url do
            route_method = route.http_method.to_s.upcase

            pass if params[:method] && params[:method] != route_method

            desc = route.action.describe
            desc[:url] = route.url
            desc[:method] = route_method
            desc[:help] = "#{route.url}?method=#{route_method}"

            JSON.pretty_generate(desc)
          end
        end

        def describe
          ret = {
              default_version: @default_version,
              versions: {default: describe_version(@default_version)},
          }

          @versions.each do |v|
            ret[:versions][v] = describe_version(v)
          end

          ret
        end

        def describe_version(v)
          ret = {resources: {}, help: version_prefix(v)}

          #puts JSON.pretty_generate(@routes)

          @routes[v].each do |resource, children|
            r_name = resource.to_s.demodulize.underscore

            ret[:resources][r_name] = describe_resource(resource, children)
          end

          ret
        end

        def describe_resource(r, hash)
          ret = {description: r.desc, actions: {}, resources: {}}

          hash[:actions].each do |action, url|
            a_name = action.to_s.demodulize.underscore
            route_method = action.http_method.to_s.upcase

            ret[:actions][a_name] = action.describe
            ret[:actions][a_name].update({
                                             url: url,
                                             method: route_method,
                                             help: "#{url}?method=#{route_method}"
                                         })
          end

          hash[:resources].each do |resource, children|
            ret[:resources][resource.to_s.demodulize.underscore] = describe_resource(resource, children)
          end

          ret
        end

        def version_prefix(v)
          "#{@root}v#{v}/"
        end
      end
    end
  end
end
