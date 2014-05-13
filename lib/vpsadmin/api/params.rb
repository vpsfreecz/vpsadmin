module VpsAdmin
  module API
    class ValidationError < Exception
      def initialize(errors)
        @errors = errors
      end

      def to_hash
        @errors
      end
    end

    class Param
      attr_reader :name, :label, :desc, :type

      def initialize(name, required: nil, label: nil, desc: nil, type: nil, db_name: nil)
        @required = required
        @name = name
        @label = label || name.to_s.capitalize
        @desc = desc
        @type = type
        @db_name = db_name
        @layout = :custom
        @validators = {}
      end

      def db_name
        @db_name || @name
      end

      def required?
        @required
      end

      def optional?
        !@required
      end

      def add_validator(v)
        @validators.update(v)
      end

      def validators
        @validators
      end

      def describe
        {
            required: required?,
            label: @label,
            description: @desc,
            type: @type ? @type.to_s : String.to_s,
            validators: @validators,
        }
      end
    end

    class Params
      attr_reader :namespace, :layout, :params

      def initialize(action, namespace)
        @params = []
        @action = action
        @namespace = namespace.to_sym
        @layout = :object
      end

      def requires(*args)
        add_param(*apply(args, required: true))
      end

      def optional(*args)
        add_param(*apply(args, required: true))
      end

      def string(*args)
        add_param(*apply(args, type: String))
      end

      def id(*args)
        integer(*args)
      end

      def foreign_key(*args)
        integer(*args)
      end

      def bool(*args)
        add_param(*apply(args, type: Boolean))
      end

      def integer(*args)
        add_param(*apply(args, type: Integer))
      end

      def datetime(*args)
        add_param(*apply(args, type: Datetime))
      end

      def param(*args)
        add_param(*args)
      end

      def use(name)
        block = @action.resource.params(name)

        instance_eval(&block) if block
      end

      # Action returns custom data.
      def custom_structure(name, s)
        @namespace = name
        @layout = :custom
        @structure = s
      end

      # Action returns a list of objects.
      def list_of_objects
        @layout = :list
      end

      # Action returns properties describing one object.
      def object
        @layout = :object
      end

      def load_validators(model)
        tr = ValidatorTranslator.new(@params)

        model.validators.each do |validator|
          tr.translate(validator)
        end
      end

      def describe
        ret = {parameters: {}}
        ret[:layout] = @layout
        ret[:namespace] = @namespace
        ret[:format] = @structure if @structure

        @params.each do |p|
          ret[:parameters][p.name] = p.describe
        end

        ret
      end

      def validate(params)
        errors = {}

        @params.each do |p|
          next unless p.required?

          if params[@namespace].nil? || !valid_layout?(params) || params[@namespace][p.name].nil?
            errors[p.name] = ['required parameter missing']
          end
        end

        unless errors.empty?
          raise ValidationError.new(errors)
        end

        params
      end

      private
        def add_param(*args)
          @params << Param.new(*args)
        end

        def apply(args, default)
          args << {} unless args.last.is_a?(Hash)
          args.last.update(default)
          args
        end

        def valid_layout?(params)
          case @layout
            when :object
              params[@namespace].is_a?(Hash)

            when :list
              params[@namespace].is_a?(Array)

            else
              false
          end
        end
    end
  end
end
