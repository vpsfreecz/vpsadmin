module VpsAdmin::API
  # Contains method to register and access selected dataset.
  # properties.
  module DatasetProperties
    # Register and store of properties.
    module Registrator
      def self.property(name, &block)
        @properties ||= {}

        p = Property.new(name)
        p.instance_exec(&block)

        @properties[name] = p
      end

      def self.properties
        @properties
      end
    end

    # Represents a single dataset property.
    class Property
      SETTABLES = %i(type inheritable)
      META = %i(label desc default choices)

      SETTABLES.each do |s|
        define_method(s) do |v|
          instance_variable_set(:"@#{s}", v)
        end
      end

      META.each do |m|
        define_method(m) do |v|
          @meta[m] = v
        end
      end

      attr_reader :meta

      def initialize(name)
        @name = name
        @meta = {}
      end

      # Register validation block.
      def validate(&block)
        @validate = block
      end

      # Add param to API representing this property.
      # +api+ is an instance of HaveAPI::Params (self in Action::input
      # or Action::output).
      def to_param(api)
        api.send(@type, *[@name, @meta])
      end

      # Returns true if the property is inheritable.
      # It is inheritable by default.
      def inheritable?
        @inheritable.nil? || @inheritable === true
      end

      def valid?(value)
        return true unless @validate

        @validate.call(value)
      end
    end

    # When included in a model, it defines access method for each
    # registered property.
    module Model
      def self.included(model)
        Registrator.properties.each_key do |name|
          model.send(:define_method, name) do
            self.dataset_properties.each do |p|
              return p.value if p.name.to_sym == name
            end

            nil
          end
        end
      end
    end

    # Call this to register properties. +block+ is executed in context
    # of module Registrator.
    def self.register(&block)
      Registrator.module_exec(&block)
    end

    # Add params to the API representing all registered properties.
    # +api+ is an instance of HaveAPI::Params (self in Action::input
    # or Action::output).
    def self.to_params(api)
      Registrator.properties.each_value do |p|
        p.to_param(api)
      end
    end

    # Can be called from a controller to validate given parameters.
    # Filtered set of valid properties is returned.
    def self.validate_params(input)
      ret = {}

      Registrator.properties.each do |name, p|
        next if input[name].nil?

        raise Exceptions::PropertyInvalid, name unless p.valid?(input[name])
        ret[name] = input[name]
      end

      ret
    end

    def self.exists?(name)
      Registrator.properties.has_key?(name)
    end

    def self.property(name)
      Registrator.properties[name]
    end
  end
end
