require 'libosctl'

module NodeCtld
  class NetAccounting::Interface
    # VPS ID
    # @return [Integer]
    attr_reader :vps_id

    # User ID
    # @param [Integer]
    # @return [Integer]
    attr_accessor :user_id

    # Network interface ID
    # @return [Integer]
    attr_reader :id

    # Network interface name as seen inside the VPS
    # @param [String]
    # @return [String]
    attr_accessor :vps_name

    # @param vps_id [Integer]
    # @param user_id [Integer]
    # @param id [Integer] network interface ID
    # @param vps_name [String]
    def initialize(vps_id, user_id, id, vps_name, bytes_in: 0, bytes_out: 0, packets_in: 0, packets_out: 0)
      @vps_id = vps_id
      @user_id = user_id
      @id = id
      @vps_name = vps_name
      @last_bytes_in = bytes_in
      @last_bytes_out = bytes_out
      @last_packets_in = packets_in
      @last_packets_out = packets_out
      @bytes_in = 0
      @bytes_out = 0
      @packets_in = 0
      @packets_out = 0
      @log_bytes_in = 0
      @log_bytes_out = 0
      @log_packets_in = 0
      @log_packets_out = 0
      @delta = 1
      @changed = false
      @reader = OsCtl::Lib::NetifStats.new
    end

    # Read stats from `/sys/class/net`
    def update(host_name)
      now = Time.now.utc
      @last_update ||= now
      @last_log ||= now

      @reader.reset
      stats = @reader.get_stats_for(host_name)

      @bytes_in = [stats[:tx][:bytes] - @last_bytes_in, 0].max
      @bytes_out = [stats[:rx][:bytes] - @last_bytes_out, 0].max

      @packets_in = [stats[:tx][:packets] - @last_packets_in, 0].max
      @packets_out = [stats[:rx][:packets] - @last_packets_out, 0].max

      @log_bytes_in += @bytes_in
      @log_bytes_out += @bytes_out

      @log_packets_in += @packets_in
      @log_packets_out += @packets_out

      @last_bytes_in = stats[:tx][:bytes]
      @last_bytes_out = stats[:rx][:bytes]

      @last_packets_in = stats[:tx][:packets]
      @last_packets_out = stats[:rx][:packets]

      @delta = [now - @last_update, 1].max.round
      @last_update = now
      @changed = true
    end

    def changed?
      @changed
    end

    def export_accounting?(log_interval)
      @last_log + log_interval <= @last_update
    end

    def export_monitor
      @changed = false

      {
        id: @id,
        time: @last_update.to_i,
        bytes_in: @bytes_in,
        bytes_out: @bytes_out,
        packets_in: @packets_in,
        packets_out: @packets_out,
        delta: @delta,
        bytes_in_readout: @last_bytes_in,
        bytes_out_readout: @last_bytes_out,
        packets_in_readout: @last_packets_in,
        packets_out_readout: @last_packets_out,
      }
    end

    def export_accounting
      ret = {
        id: @id,
        user_id: @user_id,
        time: @last_update.to_i,
        bytes_in: @log_bytes_in,
        bytes_out: @log_bytes_out,
        packets_in: @log_packets_in,
        packets_out: @log_packets_out,
      }

      @log_bytes_in = 0
      @log_bytes_out = 0
      @log_packets_in = 0
      @log_packets_out = 0
      @last_log = @last_update

      ret
    end

    def dump
      {
        vps_id: @vps_id,
        user_id: @user_id,
        netif_id: @id,
        vps_name: @vps_name,
        bytes_in: @bytes_in,
        bytes_out: @bytes_out,
        packets_in: @packets_in,
        packets_out: @packets_out,
        log_bytes_in: @log_bytes_in,
        log_bytes_out: @log_bytes_out,
        log_packets_in: @log_packets_in,
        log_packets_out: @log_packets_out,
        last_bytes_in: @last_bytes_in,
        last_bytes_out: @last_bytes_out,
        last_packets_in: @last_packets_in,
        last_packets_out: @last_packets_out,
        delta: @delta,
        last_update: @last_update && @last_update.to_i,
        last_log: @last_log && @last_log.to_i,
      }
    end
  end
end
