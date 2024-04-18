module VpsAdmin::API::Plugin
  class MetricsBase
    # @return [Prometheus::Client::Registry]
    attr_reader :registry

    # @return [::MetricsAccessToken]
    attr_reader :token

    # @return [::User]
    attr_reader :user

    # @param registry [Prometheus::Client::Registry]
    # @param token [::MetricsAccessToken]
    def initialize(registry, token)
      @registry = registry
      @token = token
      @user = token.user
    end

    # Register metrics within the registry
    def setup; end

    # Set metric values
    def compute; end

    protected

    # Register metric within the registry
    # @param type [Symbol] metric type, e.g. `:gauge`
    # @param name [Symbol] metric name
    # @param docstring [String]
    # @param labels [Array<Symbol>]
    def add_metric(type, name, docstring: '', labels: [])
      @registry.send(type, :"#{@token.metric_prefix}#{name}", docstring:, labels:)
    end
  end
end
