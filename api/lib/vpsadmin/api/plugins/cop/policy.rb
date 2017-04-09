module VpsAdmin::API::Plugins::Cop
  class Policy
    attr_reader :name

    def initialize(name, opts)
      @name = name
      @opts = opts
    end

    %i(period check_count cooldown label).each do |name|
      define_method(name) { @opts[name] }
    end

    def check_count
      policy_violation_logs.count
    end

    def check
      ret = []

      @opts[:query].call.each do |obj|
        v = @opts[:value].call(obj)
        passed = @opts[:check].call(obj, v)

        unless passed
          warn "#{obj.class.name} ##{obj.id} did not pass '#{@name}': value '#{v}'"
        end

        ret << PolicyViolation.report!(self, obj, v, passed)
      end

      ret.compact!
      ret
    end
  end
end
