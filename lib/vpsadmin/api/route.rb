module VpsAdmin
  module API
    class Route
      attr_reader :url, :action

      def initialize(url, action)
        @url = url
        @action = action
      end

      def http_method
        @action.http_method
      end

      def description
        @action.desc
      end

      def params
        @action.params
      end
    end
  end
end