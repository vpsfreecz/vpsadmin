module VpsAdmin
  module API
    class Common
      class << self
        attr_accessor :custom_attrs

        def has_attr(name, default=nil)
          @custom_attrs ||= []
          @custom_attrs << name

          instance_variable_set("@#{name}", default)

          self.class.send(:define_method, name) do |value=nil|
            if value.nil?
              instance_variable_get("@#{name}")
            else
              instance_variable_set("@#{name}", value)
            end
          end
        end

        # Called before subclass defines it's attributes (before has_attr or custom
        # attr setting), so copy defaults from parent and let it override it.
        def inherit_attrs(subclass)
          return unless @custom_attrs

          subclass.custom_attrs = []

          @custom_attrs.each do |attr|
            # puts "#{subclass}: Inherit #{attr} = #{instance_variable_get("@#{attr}")}"
            subclass.method(attr).call(instance_variable_get("@#{attr}"))
            subclass.custom_attrs << attr
          end
        end
      end

      has_attr :obj_type
    end
  end
end
