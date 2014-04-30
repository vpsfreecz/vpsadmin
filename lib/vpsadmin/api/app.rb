module VpsAdmin
  module API
    def self.resources
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

    def self.filter_resources
      ret = []

      resources do |r|
        ret << r if yield(r)
      end

      ret
    end

    def self.get_version(v)
      return resources if v == :all

      filter_resources do |r|
        r.version.is_a?(Array) ? v.include?(r.version) : r.version == v
      end
    end

    def self.use_version(v)
      App.resources ||= []
      App.resources += get_version(v)
      App.resources.uniq!
    end

    def self.mount(path, resources=nil)
      App.mount(path, resources)
    end

    def self.start!
      App.start!
    end

    class App < Sinatra::Base
      class << self
        attr_accessor :resources

        def mount(prefix='/', resources=nil)
          resources ||= @resources

          resources.each do |r|
            r.routes(prefix).each do |r|
              self.method(r.http_method).call(r.url) do
                action = r.action.new(params)
                action.exec
              end

              options r.url do
                desc = r.action.describe
                desc[:url] = r.url
                desc[:method] = r.http_method.to_s.upcase

                JSON.pretty_generate(desc)
              end
            end
          end
        end
      end
    end
  end
end
