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
    # # If no default version is set, the last included version is used.
    def self.mount(path)
      App.mount(path)
    end

    # Start API.
    def self.start!
      App.start!
    end

    class App < Sinatra::Base
      class << self
        attr_accessor :versions, :default_version, :root, :routes

        def mount(prefix='/')
          @root = prefix
          @routes = {}

          # Mount root
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

          options prefix do
            JSON.pretty_generate(App.describe_version(v))
          end

          API.get_version_resources(v).each do |resource|
            @routes[v][resource] = {resources: {}, actions: {}}

            resource.routes(prefix).each do |route|
              if route.is_a?(Hash)
                @routes[v][resource][:resources][route.keys.first] = mount_nested_resource(route.values.first)

              else
                @routes[v][resource][:actions][route.action] = route.url
                mount_action(route)
              end
            end
          end
        end

        def mount_nested_resource(routes)
          ret = {resources: {}, actions: {}}

          routes.each do |route|
            if route.is_a?(Hash)
              ret[:resources][route.keys.first] = mount_nested_resource(route.values.first)

            else
              ret[:actions][route.action] = route.url
              mount_action(route)
            end
          end

          ret
        end

        def mount_action(route)
          self.method(route.http_method).call(route.url) do
            action = route.action.new(v, params)
            action.exec
          end

          options route.url do
            route_method = route.http_method.to_s.upcase

            pass if params[:method] && params[:method] != route_method

            desc = route.action.describe
            desc[:url] = route.url
            desc[:method] = route_method
            desc[:help] = "#{route_url}?method=#{route_method}"

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
          ret = {resources: {}}

          #puts JSON.pretty_generate(@routes)

          @routes[v].each do |resource, children|
            r_name = resource.to_s.demodulize.tableize

            ret[:resources][r_name] = describe_resource(children)
          end

          ret
        end

        def describe_resource(hash)
          ret = {actions: {}, resources: {}}

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
            ret[:resources][resource.to_s.demodulize.tableize] = describe_resource(children)
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
