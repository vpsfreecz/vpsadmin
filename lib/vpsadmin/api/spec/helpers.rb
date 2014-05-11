require 'rack/test'

module VpsAdmin::API
  # Contains methods for specification of API to be used in +description+ block.
  module ApiBuilder
    def use_version(v)
      before(:each) do
        @versions = v
      end
    end

    def default_version(v)
      @default_version = v
    end

    def mount_to(path)
      @mount = path
    end

    def login(*credentials)
      @username, @password = credentials

      before(:each) do
        basic_authorize(*credentials)
      end
    end
  end

  # Helper methods for specs.
  module SpecMethods
    include Rack::Test::Methods

    # This class wraps raw reply from the API and provides more friendly
    # interface.
    class ApiResponse
      def initialize(body)
        @data = JSON.parse(body, symbolize_names: true)
      end

      def status
        @data[:status]
      end

      def ok?
        @data[:status]
      end

      def failed?
        !ok?
      end

      def response
        @data[:response]
      end

      def message
        @data[:message]
      end

      def errors
        @data[:errors]
      end

      def [](k)
        @data[:response][k]
      end
    end

    def app
      api = VpsAdmin::API::Server.new
      api.use_version(@versions || :all)
      api.set_default_version(@default_version) if @default_version
      api.mount(@mount || '/')
      api.app
    end

    # Login with HTTP basic auth.
    def login(*credentials)
      basic_authorize(*credentials)
    end

    # Make API request.
    # This method is a wrapper for Rack::Test::Methods. Input parameters
    # are encoded into JSON and sent with correct Content-Type.
    def api(http_method, url, params)
      method(http_method).call(
          url,
          params.to_json,
          {'Content-Type' => 'application/json'}
      )
    end

    # Return parsed API response.
    def api_response
      @api_response ||= ApiResponse.new(last_response.body)
    end
  end
end
