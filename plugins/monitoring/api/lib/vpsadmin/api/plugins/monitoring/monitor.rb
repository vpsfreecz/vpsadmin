module VpsAdmin::API::Plugins::Monitoring
  class Monitor
    attr_reader :name

    def initialize(name, opts)
      @name = name
      @opts = opts
    end

    %i(period check_count repeat cooldown label desc access_level).each do |name|
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

        if @opts[:user]
          responsible_user = @opts[:user].call(obj, real_obj)

        elsif real_obj.respond_to?(:user)
          responsible_user = real_obj.user

        elsif obj.respond_to?(:user)
          responsible_user = obj.user

        else
          responsible_user = nil
        end

        ret << MonitoredEvent.report!(
            self,
            real_obj,
            v,
            passed,
            responsible_user
        )
      end

      ret.compact!
      ret
    end

    def call_action(state, chain, *args)
      return if @opts[:action].nil? || @opts[:action][state].nil?
      blk = VpsAdmin::API::Plugins::Monitoring.actions[@opts[:action][state]]
      fail "unknown action '#{@opts[:action][state]}'" unless blk

      chain.instance_exec(*args, &blk)
    end
  end
end
