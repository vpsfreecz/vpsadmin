module VpsAdmin::API::Plugins
  module Monitoring
    module TransactionChains ; end
    class Monitor ; end

    module Dsl
      class ConfigEnv
        def action(name, &block)
          VpsAdmin::API::Plugins::Monitoring.register_action(name, block)
        end

        def monitor(name, &block)
          env = MonitorEnv.new
          env.instance_exec(&block)

          m = Monitor.new(name, env.data)
          VpsAdmin::API::Plugins::Monitoring.register_monitor(m)
          m
        end
      end

      class MonitorEnv
        def initialize
          @data = {}
        end

        def data
          @data
        end

        %i(label period check_count repeat cooldown desc access_level).each do |name|
          define_method(name) { |v| @data[name] = v }
        end

        %i(query object value check user).each do |name|
          define_method(name) { |&block| @data[name] = block }
        end

        def action(arg)
          res = {}

          if arg.is_a?(Symbol)
            ::MonitoredEvent.states.keys.each { |v| res[v.to_sym] = arg }

          elsif arg.is_a?(Hash)
            res.update(arg)

          else
            fail "unknown arg type '#{arg.class}': pass symbol or hash"
          end

          @data[:action] ||= {}
          @data[:action].update(res)
        end
      end
    end

    def self.config(&block)
      env = Dsl::ConfigEnv.new
      env.instance_exec(&block)
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
