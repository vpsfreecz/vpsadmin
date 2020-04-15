require 'libosctl'

module NodeCtld
  class RouteList
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System

    attr_reader :log_type

    # @param ip_v [Integer]
    def initialize(ip_v, log_type)
      @index = {}
      @log_type = log_type

      JSON.parse(syscmd("ip -#{ip_v} -json route list").output).each do |route|
        index[route['dst']] = route['dev']
      end
    end

    # @param route [IPAddress]
    def include?(route)
      index.has_key?(key(route))
    end

    protected
    attr_reader :index

    def key(addr)
      if addr.ipv4? && addr.prefix == 32
        addr.to_s
      elsif addr.ipv6? && addr.prefix == 128
        addr.to_s
      else
        addr.to_string
      end
    end
  end
end
