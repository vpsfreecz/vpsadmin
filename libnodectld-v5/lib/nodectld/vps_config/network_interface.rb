module NodeCtld
  class VpsConfig::NetworkInterface
    # @param data [Hash]
    def self.load(data)
      netif = new(
        host_name: data.fetch('host_name'),
        guest_name: data.fetch('guest_name'),
        host_mac: data.fetch('host_mac'),
        guest_mac: data.fetch('guest_mac')
      )

      netif.load_routes(data.fetch('routes'))
      netif.load_ip_addresses(data.fetch('ip_addresses'))

      netif
    end

    # @return [String]
    attr_accessor :host_name

    # @return [String]
    attr_accessor :guest_name

    # @return [String]
    attr_accessor :host_mac

    # @return [String]
    attr_accessor :guest_mac

    # @return ['routed']
    attr_reader :type

    # @return [false]
    attr_reader :dhcp

    # @return [Hash<Integer, Array<Route>>]
    attr_reader :routes

    # @return [Hash<Integer, Array<String>>]
    attr_reader :ip_addresses

    def initialize(host_name:, guest_name:, host_mac:, guest_mac:)
      @host_name = host_name
      @guest_name = guest_name
      @host_mac = host_mac
      @guest_mac = guest_mac
      @type = 'routed'
      @dhcp = false
      @routes = { 4 => [], 6 => [] }
      @ip_addresses = { 4 => [], 6 => [] }
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
      routes[address.ipv4? ? 4 : 6].detect { |v| v.address == address }
    end

    # @param ip_v [4, 6]
    # @param addr [String]
    def add_ip(ip_v, addr)
      ip_addresses[ip_v] << addr
    end

    # @param ip_v [4, 6]
    # @param addr [String]
    def remove_ip(ip_v, addr)
      ip_addresses[ip_v].delete(addr)
    end

    # @return [Hash]
    def save
      {
        'host_name' => host_name,
        'guest_name' => guest_name,
        'type' => type,
        'dhcp' => dhcp,
        'host_mac' => host_mac,
        'guest_mac' => guest_mac,
        'routes' => [4, 6].to_h do |ip_v|
          ["v#{ip_v}", routes[ip_v].map(&:save)]
        end,
        'ip_addresses' => [4, 6].to_h do |ip_v|
          ["v#{ip_v}", ip_addresses[ip_v]]
        end
      }
    end

    # @param data [Hash]
    def load_routes(data)
      @routes = [4, 6].to_h do |ip_v|
        [
          ip_v,
          data["v#{ip_v}"].map { |route| VpsConfig::Route.load(route) }
        ]
      end
    end

    def load_ip_addresses(data)
      @ip_addresses = [4, 6].to_h do |ip_v|
        [
          ip_v,
          data["v#{ip_v}"]
        ]
      end
    end
  end
end
