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

      # Apply restrictions on query which selects objects from database.
      # Most common usage is restrict user to access only objects he owns.
      def restrict(*args)
        @restrict << args.first
      end

      # Restrict parameters client can set/change.
      # [whitelist]  allow only listed parameters
      # [blacklist]  allow all parameters except listed ones
      def input(whitelist: nil, blacklist: nil)
        @input = {
            whitelist: whitelist,
            blacklist: blacklist,
        }
      end

      # Restrict parameters client can retrieve.
      # [whitelist]  allow only listed parameters
      # [blacklist]  allow all parameters except listed ones
      def output(whitelist: nil, blacklist: nil)
        @output = {
            whitelist: whitelist,
            blacklist: blacklist,
        }
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

      def filter_input(params)
        filter_inner(@input, params)
      end

      def filter_output(params)
        filter_inner(@output, params)
      end

      private
        def filter_inner(hash, params)
          return params unless hash

          if hash[:whitelist]
            ret = {}

            hash[:whitelist].each do |p|
              ret[p] = params[p] if params
            end

            ret

          elsif hash[:blacklist]
            ret = params.dup

            hash[:blacklist].each do |p|
              ret.delete(p)
            end

            ret

          else
            params
          end
        end
    end
  end
end
