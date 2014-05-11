require 'rack/test'

module VpsAdmin::API
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

  module SpecMethods
    include Rack::Test::Methods

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

    def login(*credentials)
      basic_authorize(*credentials)
    end

    def api_response
      @api_response ||= ApiResponse.new(last_response.body)
    end
  end
end
