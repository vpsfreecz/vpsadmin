require 'ipaddress'

module NodeCtld
  class VpsConfig::Route
    # @param data [Hash]
    def self.load(data)
      addr = IPAddress.parse(data['address'])
      new(
        addr,
        data['via'],
        data['class_id'],
        data['max_tx'],
        data['max_rx'],
      )
    end

    # @return [IPAddress]
    attr_reader :address

    # @return [Integer]
    attr_reader :version

    # @return [String]
    attr_reader :via

    # @return [Integer]
    attr_reader :class_id

    # @return [Integer]
    attr_reader :max_tx

    # @return [Integer]
    attr_reader :max_rx

    def initialize(address, via, class_id, max_tx, max_rx)
      @address = address
      @version = address.ipv4? ? 4 : 6
      @via = via
      @class_id = class_id
      @max_tx = max_tx
      @max_rx = max_rx
    end

    def ==(other)
      address == other.address
    end

    # @return [Hash]
    def save
      {
        'address' => address.to_string,
        'via' => via,
        'class_id' => class_id,
        'max_tx' => max_tx,
        'max_rx' => max_rx,
      }
    end
  end
end
