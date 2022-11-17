require 'libosctl'

module NodeCtld
  class NetAccounting::Interface
    # VPS ID
    # @return [Integer]
    attr_reader :vps_id

    # Network interface ID
    # @return [Integer]
    attr_reader :id

    # Network interface name as seen inside the VPS
    # @param [String]
    # @return [String]
    attr_accessor :vps_name

    # @param vps_id [Integer]
    # @param id [Integer] network interface ID
    # @param vps_name [String]
    def initialize(vps_id, id, vps_name, bytes_in: 0, bytes_out: 0, packets_in: 0, packets_out: 0)
      @vps_id = vps_id
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
      @last_update_str = @last_update.strftime('%Y-%m-%d %H:%M:%S')
      @changed = true
    end

    def changed?
      @changed
    end

    # Save state to the database
    def save(db, log_interval)
      save_monitor(db)

      if @last_log + log_interval <= @last_update
        save_accounting(db)

        @log_bytes_in = 0
        @log_bytes_out = 0
        @log_packets_in = 0
        @log_packets_out = 0
        @last_log = @last_update
      end

      @changed = false
    end

    def dump
      {
        vps_id: @vps_id,
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

    protected
    def save_monitor(db)
      db.prepared(
        'INSERT INTO network_interface_monitors SET
          network_interface_id = ?,
          bytes = ?,
          bytes_in = ?,
          bytes_out = ?,
          packets = ?,
          packets_in = ?,
          packets_out = ?,
          delta = ?,
          bytes_in_readout = ?,
          bytes_out_readout = ?,
          packets_in_readout = ?,
          packets_out_readout = ?,
          created_at = ?,
          updated_at = ?
        ON DUPLICATE KEY UPDATE
          bytes = values(bytes),
          bytes_in = values(bytes_in),
          bytes_out = values(bytes_out),
          packets = values(packets),
          packets_in = values(packets_in),
          packets_out = values(packets_out),
          delta = values(delta),
          bytes_in_readout = values(bytes_in_readout),
          bytes_out_readout = values(bytes_out_readout),
          packets_in_readout = values(packets_in_readout),
          packets_out_readout = values(packets_out_readout),
          updated_at = values(updated_at)
        ',
        @id,
        @bytes_in + @bytes_out,
        @bytes_in,
        @bytes_out,
        @packets_in + @packets_out,
        @packets_in,
        @packets_out,
        @delta,
        @last_bytes_in,
        @last_bytes_out,
        @last_packets_in,
        @last_packets_out,
        @last_update_str,
        @last_update_str,
      )
    end

    def save_accounting(db)
      kinds = {year: 'yearly', month: 'monthly', day: 'daily'}
      date_spec = {}

      kinds.each do |kind, table|
        date_spec[kind.to_s] = @last_update.send(kind)

        db.prepared(
          "INSERT INTO network_interface_#{table}_accountings SET
            network_interface_id = ?,
            #{date_spec.map { |k, v| "`#{k}` = #{v}" }.join(', ')},
            bytes_in = ?,
            bytes_out = ?,
            packets_in = ?,
            packets_out = ?,
            created_at = ?,
            updated_at = ?
          ON DUPLICATE KEY UPDATE
            bytes_in = bytes_in + values(bytes_in),
            bytes_out = bytes_out + values(bytes_out),
            packets_in = packets_in + values(packets_in),
            packets_out = packets_out + values(packets_out),
            updated_at = values(updated_at)
          ",
          @id,
          @log_bytes_in,
          @log_bytes_out,
          @log_packets_in,
          @log_packets_out,
          @last_update_str,
          @last_update_str,
        )
      end
    end
  end
end
