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
        puts 'handling'
        p v
      end
    end
  end
end
