module VpsAdmin::API::Plugins::Cop::Dsl
  class Policy
    attr_reader :name

    def initialize(name, opts)
      @name = name
      @opts = opts
    end

    def period
      @opts[:period]
    end

    def check
      @opts[:query].call.each do |obj|
        v = @opts[:value].call(obj)
        passed = @opts[:check].call(obj, v)

        unless passed
          warn "#{obj.class.name} ##{obj.id} did not pass '#{@name}': value '#{v}'"
        end

        PolicyViolation.report!(self, obj, v, passed)
      end
    end
  end
end
