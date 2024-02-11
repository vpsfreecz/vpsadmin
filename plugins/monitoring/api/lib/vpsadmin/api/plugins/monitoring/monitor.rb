module VpsAdmin::API::Plugins::Monitoring
  class Monitor
    attr_reader :name

    def initialize(name, opts)
      @name = name
      @opts = opts
    end

    %i[
      period
      check_count
      repeat
      cooldown
      label
      desc
      access_level
      skip_acknowledged
      skip_ignored
    ].each do |name|
      define_method(name) { @opts[name] }
    end

    def check
      @opts[:query].call.each do |obj|
        v = @opts[:value].call(obj)
        passed = @opts[:check].call(obj, v)
        real_obj = @opts[:object] ? @opts[:object].call(obj) : obj

        warn "#{real_obj.class.name} ##{real_obj.id} did not pass '#{@name}': value '#{v}'" unless passed

        responsible_user = if @opts[:user]
                             @opts[:user].call(obj, real_obj)

                           elsif real_obj.respond_to?(:user)
                             real_obj.user

                           elsif obj.respond_to?(:user)
                             obj.user

                           end

        MonitoredEvent.report!(
          self,
          real_obj,
          v,
          passed,
          responsible_user
        )
      end

      nil
    end

    def call_action(state, chain, *args)
      return if @opts[:action].nil? || @opts[:action][state].nil?

      blk = VpsAdmin::API::Plugins::Monitoring.actions[@opts[:action][state]]
      raise "unknown action '#{@opts[:action][state]}'" unless blk

      chain.instance_exec(*args, &blk)
    end
  end
end
