module NodeCtld
  class VpsStatus::NetworkInterface
    # @return [Integer]
    attr_reader :id

    # @return [String]
    attr_reader :host_name

    def initialize(opts)
      @id = opts.fetch('id')
      @host_name = opts.fetch('host_name')
      @last_bytes_in = opts.fetch('bytes_in_readout') || 0
      @last_bytes_out = opts.fetch('bytes_out_readout') || 0
      @last_packets_in = opts.fetch('packets_in_readout') || 0
      @last_packets_out = opts.fetch('packets_out_readout') || 0
      @bytes_in = 0
      @bytes_out = 0
      @packets_in = 0
      @packets_out = 0
    end

    def set(ifinfo)
      @bytes_in = [ifinfo.tx_bytes - @last_bytes_in, 0].max
      @bytes_out = [ifinfo.rx_bytes - @last_bytes_out, 0].max

      @packets_in = [ifinfo.tx_packets - @last_packets_in, 0].max
      @packets_out = [ifinfo.rx_packets - @last_packets_out, 0].max

      @last_bytes_in = ifinfo.tx_bytes
      @last_bytes_out = ifinfo.rx_bytes

      @last_packets_in = ifinfo.tx_packets
      @last_packets_out = ifinfo.rx_packets
    end

    def export
      {
        id: @id,
        bytes_in: @bytes_in,
        bytes_out: @bytes_out,
        packets_in: @packets_in,
        packets_out: @packets_out,
        bytes_in_readout: @last_bytes_in,
        bytes_out_readout: @last_bytes_out,
        packets_in_readout: @last_packets_in,
        packets_out_readout: @last_packets_out
      }
    end
  end
end
