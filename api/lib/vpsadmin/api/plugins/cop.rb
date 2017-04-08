module VpsAdmin::API::Plugins
  module Cop
    class Policy ; end

    module Dsl
      class PolicyEnv
        def initialize
          @data = {}
        end

        def data
          @data
        end

        %i(label period).each do |name|
          define_method(name) { |v| @data[name] = v }
        end

        %i(query value check).each do |name|
          define_method(name) { |&block| @data[name] = block }
        end
      end

      def policy(name, &block)
        env = PolicyEnv.new
        env.instance_exec(&block)

        p = Policy.new(name, env.data)
        VpsAdmin::API::Plugins::Cop.register(p)
        p
      end
    end

    def self.register(policy)
      @policies ||= []
      @policies << policy
    end

    def self.policies
      @policies
    end
  end
end

include VpsAdmin::API::Plugins::Cop::Dsl
