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
      @index = Hash[netifs.map { |n| [n.name, n] }]
    end

    # @param name [String]
    def [](name)
      @index[name]
    end

    # @param netif [VpsConfig::NetworkInterface]
    def <<(netif)
      if @index.has_key?(netif.name)
        raise ArgumentError, "netif '#{netif.name}' already exists"
      end

      @netifs << netif
      @index[netif.name] = netif
    end

    # @param name [String]
    # @param new_name [String]
    def rename(name, new_name)
      netif = @netifs.detect { |n| n.name == name }
      fail "netif '#{name}' not found" if netif.nil?
      netif.name = new_name
      @index.delete(name)
      @index[netif.name] = netif.name
    end

    # @param name [String]
    def remove(name)
      @netifs.delete_if { |n| n.name == name }
      @index.delete(name)
    end

    # @yieldparam netif [VpsConfig::NetworkInterface]
    def each(&block)
      @netifs.clone.each(&block)
    end

    include Enumerable

    # @return [Array]
    def save
      @netifs.map(&:save)
    end
  end
end
