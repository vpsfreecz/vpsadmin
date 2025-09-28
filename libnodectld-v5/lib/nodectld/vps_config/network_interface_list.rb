module NodeCtld
  class VpsConfig::NetworkInterfaceList
    # @param data [Array]
    def self.load(data)
      netifs = data.map do |v|
        VpsConfig::NetworkInterface.load(v)
      end

      new(netifs)
    end

    # @param netifs [Array<VpsConfig::NetworkInterface>]
    def initialize(netifs = [])
      @netifs = netifs
      @index = netifs.to_h { |n| [n.guest_name, n] }
    end

    # @param guest_name [String]
    def [](guest_name)
      @index[guest_name]
    end

    # @param netif [VpsConfig::NetworkInterface]
    def <<(netif)
      raise ArgumentError, "netif '#{netif.guest_name}' already exists" if @index.has_key?(netif.guest_name)

      @netifs << netif
      @index[netif.guest_name] = netif
    end

    # @param guest_name [String]
    # @param new_guest_name [String]
    def rename(guest_name, new_guest_name)
      netif = @netifs.detect { |n| n.guest_name == guest_name }
      raise "netif '#{guest_name}' not found" if netif.nil?

      netif.guest_name = new_guest_name
      @index.delete(guest_name)
      @index[netif.guest_name] = netif.guest_name
    end

    # @param guest_name [String]
    def remove(guest_name)
      @netifs.delete_if { |n| n.guest_name == guest_name }
      @index.delete(guest_name)
    end

    # @yieldparam netif [VpsConfig::NetworkInterface]
    def each(&)
      @netifs.clone.each(&)
    end

    include Enumerable

    # @return [Array]
    def save
      @netifs.map(&:save)
    end
  end
end
