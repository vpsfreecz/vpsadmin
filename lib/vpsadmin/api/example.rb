module VpsAdmin
  module API
    class Example
      def request(f)
        @request = f
      end

      def response(f)
        @response = f
      end

      def comment(str)
        @comment = str
      end

      def provided?
        @request || @response || @comment
      end

      def describe
        if provided?
          {
              request: @request,
              response: @response,
              comment: @comment
          }
        else
          {}
        end
      end
    end
  end
end
