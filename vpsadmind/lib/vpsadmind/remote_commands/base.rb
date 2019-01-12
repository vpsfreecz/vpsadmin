module VpsAdmind
  module RemoteCommands
    class Base
      def self.handle(name)
        VpsAdmind::RemoteControl.register(name, self)
      end

      include VpsAdmind::Utils::Command

      needs :log

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
        {ret: :ok}
      end

      def error
        {ret: :error}
      end
    end
  end
end
