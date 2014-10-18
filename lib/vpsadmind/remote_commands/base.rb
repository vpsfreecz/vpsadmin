module VpsAdmind
  module RemoteCommands
    class Base
      def self.handle(name)
        VpsAdmind::RemoteControl.register(self.to_s, name)
      end

      def initialize(params, daemon)
        @daemon = daemon

        params.each do |k, v|
          instance_variable_set("@#{k}", v)
        end
      end

      def exec

      end

      protected
      def ok
        {:ret => :ok}
      end
    end
  end
end
