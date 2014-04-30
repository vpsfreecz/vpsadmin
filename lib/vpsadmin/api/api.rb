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
        attr_accessor :versions, :default_version

        def mount(prefix='/')
          # Mount root
          # FIXME

          @default_version ||= versions.last

          # Mount default version first
          mount_version(prefix, @default_version)

          @versions.each do |v|
            mount_version("#{prefix}v#{v}/", v)
          end
        end

        def mount_version(prefix, v)
          API.get_version_resources(v).each do |resource|
            resource.routes(prefix).each do |route|
              self.method(route.http_method).call(route.url) do
                action = route.action.new(v, params)
                action.exec
              end

              options route.url do
                desc = route.action.describe
                desc[:url] = route.url
                desc[:method] = route.http_method.to_s.upcase

                JSON.pretty_generate(desc)
              end
            end
          end
        end
      end
    end
  end
end
