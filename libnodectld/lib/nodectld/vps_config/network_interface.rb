module NodeCtld
  class VpsConfig::NetworkInterface
    # @parma data [Hash]
    def self.load(data)
      netif = new(data['name'])
      netif.load_routes(data['routes'])
      netif
    end

    # @param [String]
    # @return [String]
    attr_accessor :name

    # @return [Hash<Integer, Array<Route>>]
    attr_reader :routes

    # @param name [String]
    def initialize(name)
      @name = name
      @routes = {4 => [], 6 => []}
    end

    # @param data [Hash]
    def load_routes(data)
      @routes = parse_ip_addresses(data)
    end

    # @param route [VpsConfig::Route]
    def add_route(route)
      routes[route.version] << route
    end

    # @param route [VpsConfig::Route]
    def remove_route(route)
      routes[route.version].delete(route)
    end

    # @param address [IPAddress]
    def has_route_for?(address)
      !route_for(address).nil?
    end

    # @param address [IPAddress]
    def route_for(address)
      routes[ address.ipv4? ? 4 : 6 ].detect { |v| v.address == address }
    end

    # @return [Hash]
    def save
      {
        'name' => name,
        'routes' => Hash[[4, 6].map do |ip_v|
          [ip_v, routes[ip_v].map(&:save)]
        end],
      }
    end

    protected
    def parse_ip_addresses(ips)
      Hash[[4, 6].map do |ip_v|
        [
          ip_v,
          ips[ip_v].map { |data| VpsConfig::Route.load(data) },
        ]
      end]
    end
  end
end
