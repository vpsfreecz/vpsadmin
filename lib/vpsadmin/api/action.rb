module VpsAdmin
  module API
    class Action < Common
      obj_type :action
      has_attr :version
      has_attr :desc
      has_attr :route
      has_attr :http_method, :get
      has_attr :auth, true

      def self.inherited(subclass)
        #puts "Action.inherited called #{subclass} from #{to_s}"

        subclass.instance_variable_set(:@obj_type, obj_type)

        resource = Kernel.const_get(subclass.to_s.deconstantize)

        inherit_attrs(subclass)
        inherit_attrs_from_resource(subclass, resource, [:auth])

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
              auth: @auth,
              description: @desc,
              input: @input ? @input.describe : {},
              output: @output ? @output.describe : {},
              example: @example ? @example.describe : {},
          }
        end

        # Inherit attributes from resource action is defined in.
        def inherit_attrs_from_resource(action, r, attrs)
          begin
            return unless r.obj_type == :resource

          rescue NoMethodError
            return
          end

          attrs.each do |attr|
            action.method(attr).call(r.method(attr).call)
          end
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
