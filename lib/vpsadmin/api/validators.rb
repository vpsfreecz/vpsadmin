require 'active_record/validations'

module VpsAdmin
  module API
    class ValidatorTranslator
      class << self
        attr_reader :handlers

        def handle(validator, &block)
          @handlers ||= {}
          @handlers[validator] = block
        end
      end

      handle ActiveRecord::Validations::PresenceValidator do |v|
        validator({present: true})
      end

      handle ActiveModel::Validations::AbsenceValidator do |v|
        validator({absent: true})
      end

      handle ActiveModel::Validations::ExclusionValidator do |v|
        validator(v.options)
      end

      handle ActiveModel::Validations::FormatValidator do |v|
        validator({format: {with_source: v.options[:with].source}.update(v.options)})
      end

      handle ActiveModel::Validations::InclusionValidator do |v|
        validator(v.options)
      end

      handle ActiveModel::Validations::LengthValidator do |v|
        validator(v.options)
      end

      handle ActiveModel::Validations::NumericalityValidator do |v|
        validator(v.options)
      end

      handle ActiveRecord::Validations::UniquenessValidator do |v|
        validator(v.options)
      end

      def initialize(params)
        @params = params
      end

      def validator_for(param, v)
        @params.each do |p|
          if p.name == param
            p.add_validator(v)
            break
          end
        end
      end

      def validator(v)
        validator_for(@attr, v)
      end

      def translate(v)
        self.class.handlers.each do |klass, translator|
          if v.is_a?(klass)
            v.attributes.each do |attr|
              @attr = attr
              instance_exec(v, &translator)
            end
            break
          end
        end
      end
    end
  end
end
