module VpsAdmind
  class RouteList
    include Utils::Log
    include Utils::System

    attr_reader :log_type

    # @param ip_v [Integer]
    def initialize(ip_v)
      @index = {}

      syscmd("ip -#{ip_v} route list")[:output].strip.split("\n").each do |line|
        route, = line.split(' ')
        index[route] = true
      end
    end

    # @param route [String]
    def include?(addr)
      index.has_key?(addr)
    end

    protected
    attr_reader :index
  end
end
