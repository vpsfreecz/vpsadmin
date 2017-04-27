module VpsAdmin::API::Plugins::Monitoring
  class Monitor
    attr_reader :name

    def initialize(name, opts)
      @name = name
      @opts = opts
    end

    %i(period check_count cooldown label desc).each do |name|
      define_method(name) { @opts[name] }
    end

    def check
      ret = []

      @opts[:query].call.each do |obj|
        v = @opts[:value].call(obj)
        passed = @opts[:check].call(obj, v)
        real_obj = @opts[:object] ? @opts[:object].call(obj) : obj

        unless passed
          warn "#{real_obj.class.name} ##{real_obj.id} did not pass '#{@name}': value '#{v}'"
        end

        ret << MonitoredEvent.report!(self, real_obj, v, passed)
      end

      ret.compact!
      ret
    end

    def call_action(chain, *args)
      return unless @opts[:action]
      blk = VpsAdmin::API::Plugins::Monitoring.actions[@opts[:action]]
      fail "unknown action '#{@opts[:action]}'" unless blk

      chain.instance_exec(*args, &blk)
    end
  end
end
