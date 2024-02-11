module NodeCtld
  module RemoteCommands
    class Base
      def self.handle(name)
        NodeCtld::RemoteControl.register(to_s, name)
      end

      include NodeCtld::Utils::Command

      needs :log

      def initialize(params, daemon)
        @daemon = daemon

        params.each do |k, v|
          instance_variable_set("@#{k}", v)
        end
      end

      def exec; end

      protected

      def ok
        { ret: :ok }
      end

      def error(msg)
        { ret: :failed, output: msg }
      end
    end
  end
end
