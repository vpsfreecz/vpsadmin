module VpsAdmin
  module API
    class Action < Common
      obj_type :action
      has_attr :version
      has_attr :desc
      has_attr :route
      has_attr :http_method, :get

      def self.inherited(subclass)
        #puts "Action.inherited called #{subclass} from #{to_s}"

        subclass.instance_variable_set(:@obj_type, obj_type)
        inherit_attrs(subclass)

        resource = Kernel.const_get(subclass.to_s.deconstantize)

        begin
          subclass.instance_variable_set(:@resource, resource)
          subclass.instance_variable_set(:@model, resource.model)
        rescue NoMethodError
          return
        end
      end

      class << self
        attr_reader :resource

        def input(&block)
          if block
            @input = Params.new
            @input.instance_eval(&block)
            @input.load_validators(model) if model
          else
            @input
          end
        end

        def output(&block)
          if block
            @output = Params.new
            @output.instance_eval(&block)
          else
            @output
          end
        end

        def params(&block)

        end

        def example(&block)
          if block
            @example = Example.new
            @example.instance_eval(&block)
          else
            @example
          end
        end

        def build_route(prefix)
          prefix + (@route || to_s.demodulize.underscore) % {resource: self.resource.to_s.demodulize.underscore}
        end

        def describe
          {
              description: @desc,
              input: @input ? @input.describe : {},
              output: @output ? @output.describe : {},
              example: @example ? @example.describe : {},
          }
        end
      end

      def initialize(version, params)
        @version = version
        @params = params
      end

      def exec
        ['not implemented']
      end

      def v?(v)
        @version == v
      end
    end
  end
end
