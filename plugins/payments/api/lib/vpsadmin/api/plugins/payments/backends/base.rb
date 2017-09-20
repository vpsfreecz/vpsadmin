module VpsAdmin::API::Plugins::Payments::Backends
  class Base
    class << self
      def register(name)
        VpsAdmin::API::Plugins::Payments.register_backend(name, self)
      end
    end

    def fetch

    end
  end
end
