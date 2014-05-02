module VpsAdmin
  module API
    class Authorization
      def initialize(&block)
        @block = block
      end

      # Returns true if user is authorized.
      # Block must call allow to authorize user, default rule is deny.
      def authorized?(user)
        @restrict = []

        catch(:rule) do
          instance_exec(user, &@block)
          deny # will not be called if block throws allow
        end
      end

      def restrict(*args)
        @restrict << args.first
      end

      def allow
        throw(:rule, true)
      end

      def deny
        throw(:rule, false)
      end

      def restrictions
        ret = {}

        @restrict.each do |r|
          ret.update(r)
        end

        ret
      end
    end
  end
end
