require 'ipaddr'

module DistConfig
  class NetworkInterface
    class IpAddress
      def initialize(string)
        @addr = IPAddr.new(string)
      end

      def netmask
        @addr.netmask
      end

      def to_s
        @addr.to_s
      end

      def to_string
        "#{@addr}/#{@addr.prefix}"
      end
    end

    DEFAULT_IPV4 = '255.255.255.254'.freeze

    # @return [String]
    attr_reader :guest_name

    alias name guest_name

    # @return ['bridge', 'routed']
    attr_reader :type

    # @return [Boolean]
    attr_reader :dhcp

    # @return [String]
    attr_reader :host_mac

    # @return [String]
    attr_reader :guest_mac

    def initialize(cfg)
      @guest_name = cfg.fetch('guest_name')
      @type = cfg.fetch('type')
      @dhcp = cfg.fetch('dhcp', false)
      @host_mac = cfg.fetch('host_mac', nil)
      @guest_mac = cfg.fetch('guest_mac', nil)

      cfg_ips = cfg.fetch('ip_addresses', {})
      @ips = {
        4 => cfg_ips.fetch('v4', []).map { |v| IpAddress.new(v) },
        6 => cfg_ips.fetch('v6', []).map { |v| IpAddress.new(v) }
      }
    end

    # @return [Array]
    def active_ip_versions
      [4, 6].delete_if { |v| @ips[v].empty? }
    end

    # @param v [4, 6]
    def ips(v)
      @ips[v]
    end

    # @param v [4, 6]
    def default_via(v)
      case v
      when 4
        DEFAULT_IPV4
      when 6
        host_link_local_address
      end
    end

    protected

    def host_link_local_address
      raise 'host MAC address must be set' if @host_mac.nil?

      # Normalize MAC (strip separators, lowercase)
      parts = @host_mac.downcase.split(/[:-]/).map { |p| p.to_i(16) }
      raise ArgumentError, 'invalid MAC' unless parts.size == 6

      # Flip the 7th bit (Universal/Local bit) of the first byte
      parts[0] ^= 0x02

      # Insert ff:fe in the middle (EUI-64 expansion)
      eui64 = parts[0..2] + [0xff, 0xfe] + parts[3..5]

      # Format as IPv6 hextets
      hextets = []
      eui64.each_slice(2) { |a, b| hextets << ((a << 8) | b) }

      # Build the link-local address
      "fe80::#{hextets.map { |h| h.to_s(16) }.join(':')}"
    end
  end
end
