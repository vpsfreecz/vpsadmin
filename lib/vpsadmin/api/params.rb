module VpsAdmin
  module API
    class Param
      attr_reader :name, :label, :desc, :type

      def initialize(name, required: nil, label: nil, desc: nil, type: String)
        @required = required
        @name = name
        @label = label || name.to_s.capitalize
        @desc = desc
        @type = type
      end

      def required?
        @required
      end

      def optional?
        !@required
      end

      def validator
        'FIXME'
      end

      def describe
        {
            required: required?,
            label: @label,
            description: @desc,
            type: @type.to_s
        }
      end
    end

    class Params
      def initialize
        @params = []
      end

      def requires(*args)
        add_param(*args)
      end

      def optional(*args)
        add_param(*args)
      end

      def param(*args)
        add_param(*args)
      end

      def load_validators(model)
        puts "Load validators from #{model}"

        model.validators.each do |validator|
          ValidatorTranslator.handlers.each do |k, block|
            if validator.is_a?(k)
              instance_eval(&block)
            end
          end
        end
      end

      def describe
        ret = {}

        @params.each do |p|
          ret[p.name] = p.describe
        end

        ret
      end

      private
      def add_param(*args)
        @params << Param.new(*args)
      end
    end
  end
end
