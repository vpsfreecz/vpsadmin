module VpsAdmin::API::Plugins
  module Monitoring
    module TransactionChains; end

    module Dsl
      class ConfigEnv
        def action(name, &block)
          VpsAdmin::API::Plugins::Monitoring.register_action(name, block)
        end

        def monitor(name, &)
          env = MonitorEnv.new
          env.instance_exec(&)

          m = Monitor.new(name, env.data)
          VpsAdmin::API::Plugins::Monitoring.register_monitor(m)
          m
        end
      end

      class MonitorEnv
        def initialize
          @data = {
            skip_acknowledged: true,
            skip_ignored: true
          }
        end

        attr_reader :data

        %i[
          label
          period
          check_count
          repeat
          cooldown
          desc
          access_level
          skip_acknowledged
          skip_ignored
        ].each do |name|
          define_method(name) { |v| @data[name] = v }
        end

        %i[query object value check user].each do |name|
          define_method(name) { |&block| @data[name] = block }
        end

        def action(arg)
          res = {}

          if arg.is_a?(Symbol)
            ::MonitoredEvent.states.each_key { |v| res[v.to_sym] = arg }

          elsif arg.is_a?(Hash)
            res.update(arg)

          else
            raise "unknown arg type '#{arg.class}': pass symbol or hash"
          end

          @data[:action] ||= {}
          @data[:action].update(res)
        end
      end
    end

    def self.config(&)
      env = Dsl::ConfigEnv.new
      env.instance_exec(&)
      nil
    end

    def self.register_action(name, block)
      @actions ||= {}
      @actions[name] = block
    end

    def self.actions
      @actions
    end

    def self.register_monitor(monitor)
      @monitors ||= []
      @monitors << monitor
    end

    def self.monitors
      @monitors
    end
  end
end

include VpsAdmin::API::Plugins::Monitoring::Dsl
