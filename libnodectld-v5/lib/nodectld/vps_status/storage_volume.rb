module NodeCtld
  class VpsStatus::StorageVolume
    attr_reader :id,
                :read_requests_readout, :read_bytes_readout, :write_requests_readout, :write_bytes_readout,
                :read_requests, :read_bytes, :write_requests, :write_bytes

    def initialize(row)
      @id = row['id']
      @pool_path = row['pool_path']
      @name = row['name']
      @format = row['format']

      @read_requests_readout = row['read_requests_readout']
      @read_bytes_readout = row['read_bytes_readout']
      @write_requests_readout = row['write_requests_readout']
      @write_bytes_readout = row['write_bytes_readout']

      @read_requests = 0
      @read_bytes = 0
      @write_requests = 0
      @write_bytes = 0
    end

    def path
      if @id == 'all'
        ''
      else
        File.join(@pool_path, "#{@name}.#{@format}")
      end
    end

    def set(io_stats, prev_stats)
      @read_requests_readout = io_stats.rd_req
      @read_bytes_readout = io_stats.rd_bytes
      @write_requests_readout = io_stats.wr_req
      @write_bytes_readout = io_stats.wr_bytes

      prev_vol = prev_stats.detect { |v| v.id == id }

      if prev_vol
        @read_requests = [0, @read_requests_readout - prev_vol.read_requests_readout].max
        @read_bytes = [0, @read_bytes_readout - prev_vol.read_bytes_readout].max
        @write_requests = [0, @write_requests_readout - prev_vol.write_requests_readout].max
        @write_bytes = [0, @write_bytes_readout - prev_vol.write_bytes_readout].max
      else
        @read_requests = 0
        @read_bytes = 0
        @write_requests = 0
        @write_bytes = 0
      end
    end

    def export
      {
        'id' => id,
        'read_requests' => read_requests,
        'read_bytes' => read_bytes,
        'write_requests' => write_requests,
        'write_bytes' => write_bytes,
        'read_requests_readout' => read_requests_readout,
        'read_bytes_readout' => read_bytes_readout,
        'write_requests_readout' => write_requests_readout,
        'write_bytes_readout' => write_bytes_readout
      }
    end
  end
end
