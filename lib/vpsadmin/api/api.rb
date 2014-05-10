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
  end
end
