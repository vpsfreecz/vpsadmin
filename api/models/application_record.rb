class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  class << self
    def event_redact(*attributes)
      fields = attributes.flatten.map(&:to_s)
      duplicates = event_redacted_fields & fields
      unless duplicates.empty?
        raise ArgumentError,
              "event redaction is already declared for #{name}.#{duplicates.join(', ')}"
      end

      @event_redacted_fields = (event_redacted_fields + fields).uniq.sort.freeze
    end

    def event_redacted_fields
      @event_redacted_fields || [].freeze
    end

    def event_delete_cascades(*associations)
      names = associations.flatten.map(&:to_sym)
      duplicates = event_delete_cascade_associations & names
      unless duplicates.empty?
        raise ArgumentError,
              'event delete cascade is already declared for ' \
              "#{name}.#{duplicates.join(', ')}"
      end

      @event_delete_cascades = (
        event_delete_cascade_associations + names
      ).uniq.freeze
    end

    def event_delete_cascade_associations
      @event_delete_cascades || [].freeze
    end

    def operation_event_owner(via: nil, &resolver)
      if instance_variable_defined?(:@operation_event_owner_resolver)
        raise ArgumentError, "operation event owner is already declared for #{name}"
      end

      path = Array(via)
      if resolver.nil? && path.empty?
        raise ArgumentError, 'operation event owner requires an association path or resolver'
      end

      @operation_event_owner_resolver = resolver || lambda do |record|
        path.reduce(record) do |value, association|
          break if value.nil?

          value.public_send(association)
        end
      end
    end

    def operation_event_owner_for(record)
      @operation_event_owner_resolver&.call(record)
    end
  end
end
