module VpsAdmin
  module API
    class Action < Common
      obj_type :action
      has_attr :version
      has_attr :desc
      has_attr :route
      has_attr :http_method, :get
      has_attr :auth, true

      attr_reader :message, :errors

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
        attr_reader :resource, :authorization, :input

        def input(namespace=nil, &block)
          if block
            @input = Params.new(namespace || self.resource.to_s.demodulize.underscore)
            @input.instance_eval(&block)
            @input.load_validators(model) if model
          else
            @input
          end
        end

        def output(namespace=nil, &block)
          if block
            @output = Params.new(namespace || self.resource.to_s.demodulize.underscore)
            @output.instance_eval(&block)
          else
            @output
          end
        end

        def authorize(&block)
          @authorization = Authorization.new(&block)
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
              input: @input ? @input.describe : {parameters: {}},
              output: @output ? @output.describe : {parameters: {}},
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

      def initialize(version, params, body)
        @version = version
        @params = params.update(body) if body

        class_auth = self.class.authorization

        if class_auth
          @authorization = class_auth.clone
        else
          @authorization = Authorization.new {}
        end
      end

      def authorized?(user)
        @current_user = user
        @authorization.authorized?(user)
      end

      def current_user
        @current_user
      end

      def params
        return @safe_params if @safe_params

        @safe_params = @authorization.filter_input(@params[self.class.input.namespace])
      end

      # This method must be reimplemented in every action.
      # It must not be invoked directly, only via safe_exec, which restricts output.
      def exec
        ['not implemented']
      end

      # Calls exec while catching all exceptions and restricting output only
      # to what user can see.
      # Return array +[status, data|error]+
      def safe_exec
        ret = catch(:return) do
          begin
            exec
          rescue ActiveRecord::RecordNotFound
            error('object not found')

            # rescue => e
            #   puts "#{e} just happened"
            end
        end

        if ret
          case self.class.output.layout
            when :object
               ret = @authorization.filter_output(ret)

            when :list
              ret.map! do |obj|
                @authorization.filter_output(obj)
              end
          end

          [true, {self.class.output.namespace => ret}]

        else
          [false, @message, @errors]
        end
      end

      def v?(v)
        @version == v
      end

      protected
        def with_restricted(*args)
          if args.empty?
            @authorization.restrictions
          else
            args.first.update(@authorization.restrictions)
          end
        end

        def ok(ret)
          throw(:return, ret)
        end

        def error(msg, errs={})
          @message = msg
          @errors = errs
          throw(:return, false)
        end
    end
  end
end
