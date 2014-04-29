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

        def params(&block)
          if block
            @params = Params.new
            @params.instance_eval(&block)
            @params.load_validators(model) if model
          else
            @params
          end
        end

        def build_route(prefix)
          prefix + (@route || to_s.demodulize.underscore) % {resource: self.resource.to_s.demodulize.underscore}
        end

        def describe
          {
              description: @desc,
              parameters: @params ? @params.describe : {},
          }
        end
      end

      def initialize(params)
        @params = params
      end
    end
  end
end
