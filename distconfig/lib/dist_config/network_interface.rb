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

    DEFAULT_IPV4 = '172.31.255.254'.freeze

    DEFAULT_IPV6 = 'fe80::1'.freeze

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
      @host_name = cfg.fetch('host_name')
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
        DEFAULT_IPV6
      end
    end

    def dump
      {
        'host_name' => @host_name,
        'guest_name' => @guest_name,
        'type' => @type,
        'dhcp' => @dhcp,
        'host_mac' => @host_mac,
        'guest_mac' => @guest_mac,
        'ip_addresses' => [4, 6].to_h do |v|
          ["v#{v}", @ips[v].map(&:to_string)]
        end
      }
    end
  end
end
