require 'ipaddress'

module NodeCtld
  class VpsConfig::Route
    # @param data [Hash]
    def self.load(data)
      addr = IPAddress.parse(data['address'])
      new(addr, data['via'])
    end

    # @return [IPAddress]
    attr_reader :address

    # @return [Integer]
    attr_reader :version

    # @return [String]
    attr_reader :via

    def initialize(address, via)
      @address = address
      @version = address.ipv4? ? 4 : 6
      @via = via
    end

    def ==(other)
      address == other.address
    end

    # @return [Hash]
    def save
      {
        'address' => address.to_string,
        'via' => via
      }
    end
  end
end
